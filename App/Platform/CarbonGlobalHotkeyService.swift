// UNVERIFIED: written on Linux, compile and test on macOS
// TODO(M8-04): verify on macOS (hotkey fires with the app in background, conflicts, unregister)
#if os(macOS)
import Carbon.HIToolbox
import Foundation
import MarginCore

/// Global hotkey via Carbon `RegisterEventHotKey` (works without accessibility permission).
public final class CarbonGlobalHotkeyService: GlobalHotkeyService, @unchecked Sendable {
    private struct Registration {
        let ref: EventHotKeyRef
        let handler: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var registrations: [Shortcut: Registration] = [:]
    private var idToShortcut: [UInt32: Shortcut] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x4D52_4748 // 'MRGH'

    public init() {}

    deinit {
        for r in registrations.values { UnregisterEventHotKey(r.ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    public func register(_ shortcut: Shortcut, handler: @escaping @Sendable () -> Void) throws {
        guard let code = Self.keyCode(shortcut.key) else {
            throw MarginError.invalid("Unsupported hotkey key: \(shortcut.key)")
        }
        unregister(shortcut)
        try installEventHandlerIfNeeded()
        lock.lock(); defer { lock.unlock() }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(code, Self.carbonModifiers(shortcut.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            throw MarginError.io("Cannot register global shortcut \(shortcut) (OSStatus \(status))")
        }
        registrations[shortcut] = Registration(ref: ref, handler: handler)
        idToShortcut[id] = shortcut
    }

    public func unregister(_ shortcut: Shortcut) {
        lock.lock(); defer { lock.unlock() }
        guard let r = registrations.removeValue(forKey: shortcut) else { return }
        UnregisterEventHotKey(r.ref)
        idToShortcut = idToShortcut.filter { $0.value != shortcut }
    }

    fileprivate func fire(id: UInt32) {
        lock.lock()
        let handler = idToShortcut[id].flatMap { registrations[$0]?.handler }
        lock.unlock()
        guard let handler else { return }
        DispatchQueue.main.async(execute: handler)
    }

    private func installEventHandlerIfNeeded() throws {
        lock.lock(); defer { lock.unlock() }
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let s = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard s == noErr, hotKeyID.signature == CarbonGlobalHotkeyService.signature else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<CarbonGlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue().fire(id: hotKeyID.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard status == noErr else { throw MarginError.io("Cannot install hotkey handler (OSStatus \(status))") }
    }

    static func carbonModifiers(_ mods: Set<Shortcut.Modifier>) -> UInt32 {
        var m: UInt32 = 0
        if mods.contains(.cmd) { m |= UInt32(cmdKey) }
        if mods.contains(.shift) { m |= UInt32(shiftKey) }
        if mods.contains(.opt) { m |= UInt32(optionKey) }
        if mods.contains(.ctrl) { m |= UInt32(controlKey) }
        return m
    }

    /// Virtual key codes (ANSI layout) from `Carbon.HIToolbox` (`kVK_*`).
    static func keyCode(_ key: String) -> UInt32? {
        let table: [String: Int] = [
            "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape,
            "delete": kVK_Delete, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "left": kVK_LeftArrow, "right": kVK_RightArrow,
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
            "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
            "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17,
            "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
        ]
        return table[key].map(UInt32.init)
    }
}
#endif
