import Foundation

/// A keyboard shortcut: a set of modifiers plus one key, platform-neutral.
/// Text form is lowercase and `+`-separated in canonical order, e.g. `cmd+shift+space`.
public struct Shortcut: Sendable, Hashable, Codable, CustomStringConvertible {
    public enum Modifier: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
        // Declaration order is the canonical formatting order.
        case ctrl, opt, shift, cmd

        public static func < (a: Modifier, b: Modifier) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }

        static func parse(_ token: String) -> Modifier? {
            switch token {
            case "cmd", "command", "⌘": .cmd
            case "shift", "⇧": .shift
            case "opt", "option", "alt", "⌥": .opt
            case "ctrl", "control", "⌃": .ctrl
            default: nil
            }
        }
    }

    public let modifiers: Set<Modifier>
    /// Lowercase key name: a single letter or digit, `space`, `return`, `tab`, `escape`, `f1`…`f20`, …
    public let key: String

    /// Default quick-capture shortcut (M8-04).
    public static let quickCapture = Shortcut(modifiers: [.cmd, .shift], key: "space")

    public init(modifiers: Set<Modifier>, key: String) {
        self.modifiers = modifiers
        self.key = key.lowercased()
    }

    /// Parses `"cmd+shift+space"` (case-insensitive, spaces around `+` allowed, modifier aliases
    /// `command`/`option`/`alt`/`control`). Requires at least one modifier and exactly one valid key.
    public init(parsing text: String) throws {
        let tokens = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard tokens.count >= 2, !tokens.contains("") else {
            throw MarginError.invalid("Shortcut needs modifiers and a key: \(text)")
        }
        var mods = Set<Modifier>()
        var key: String?
        for token in tokens {
            if let m = Modifier.parse(token) {
                mods.insert(m)
            } else if key == nil, Shortcut.isValidKey(token) {
                key = token
            } else {
                throw MarginError.invalid("Unknown shortcut part '\(token)' in: \(text)")
            }
        }
        guard let key, !mods.isEmpty else {
            throw MarginError.invalid("Shortcut needs modifiers and a key: \(text)")
        }
        self.init(modifiers: mods, key: key)
    }

    /// Canonical text, e.g. `ctrl+opt+shift+cmd+k`.
    public var description: String {
        (modifiers.sorted().map(\.rawValue) + [key]).joined(separator: "+")
    }

    static let namedKeys: Set<String> = ["space", "return", "tab", "escape", "delete", "up", "down", "left", "right"]

    static func isValidKey(_ token: String) -> Bool {
        if namedKeys.contains(token) { return true }
        if token.count == 1, let c = token.unicodeScalars.first,
           (c.value >= 97 && c.value <= 122) || (c.value >= 48 && c.value <= 57) { return true }
        if token.hasPrefix("f"), let n = Int(token.dropFirst()), (1...20).contains(n) { return true }
        return false
    }
}

/// Registers a system-wide shortcut. The macOS implementation lives in `MarginPlatform`.
public protocol GlobalHotkeyService: Sendable {
    /// Registers `shortcut`; `handler` runs on the main queue each time it is pressed. Replaces a
    /// previous registration of the same shortcut. Throws `MarginError.io` when the system refuses
    /// (e.g. the combination is taken).
    func register(_ shortcut: Shortcut, handler: @escaping @Sendable () -> Void) throws
    /// Removes the registration; a no-op when `shortcut` is not registered.
    func unregister(_ shortcut: Shortcut)
}

/// Portable stand-in (tests, Linux): remembers registrations and lets tests fire them.
public final class InMemoryGlobalHotkeyService: GlobalHotkeyService, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [Shortcut: @Sendable () -> Void] = [:]

    public init() {}

    public func register(_ shortcut: Shortcut, handler: @escaping @Sendable () -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        handlers[shortcut] = handler
    }

    public func unregister(_ shortcut: Shortcut) {
        lock.lock(); defer { lock.unlock() }
        handlers[shortcut] = nil
    }

    public var registered: Set<Shortcut> {
        lock.lock(); defer { lock.unlock() }
        return Set(handlers.keys)
    }

    /// Simulates a key press. Returns `false` when nothing is registered for `shortcut`.
    @discardableResult
    public func fire(_ shortcut: Shortcut) -> Bool {
        lock.lock(); let h = handlers[shortcut]; lock.unlock()
        h?()
        return h != nil
    }
}
