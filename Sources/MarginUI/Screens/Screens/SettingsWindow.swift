import AppKit
import MarginCore
import SwiftUI

extension Workspace {
    /// Settings in their own window (Account v3 2): no title bar, the traffic lights over the sidebar.
    public func openSettings(_ section: SettingsModel.Section? = nil) {
        if let section { settingsModel().section = section }
        SettingsWindow.shared.show(self)
    }
}

/// The one settings window. It belongs to the workspace that opened it last (a vault switch makes a
/// new workspace, the next open rebuilds the content).
@MainActor
public final class SettingsWindow: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindow()
    private var window: NSWindow?
    private weak var workspace: Workspace?

    var isKey: Bool { window?.isKeyWindow == true }

    func show(_ workspace: Workspace) {
        if window == nil || self.workspace !== workspace { build(for: workspace) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Closes the window (the vault it shows went away).
    public func close() { window?.close() }

    private func build(for workspace: Workspace) {
        self.workspace = workspace
        let root = SettingsView(model: workspace.settingsModel(), inWindow: true)
            .environment(workspace)
            .overlay { DialogHost(inSettings: true).environment(workspace) }
            .overlay(alignment: .bottom) { ToastView(toast: workspace.toast).padding(.bottom, 24) }
            .frame(minWidth: 820, minHeight: 560)
        let host = NSHostingController(rootView: root)
        // Sized by the window, not the other way round: no window size limits from inside a layout pass.
        host.sizingOptions = []
        let window = self.window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                             backing: .buffered, defer: false)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 560)
        window.tabbingMode = .disallowed
        window.delegate = self
        let frame = window.frame
        window.contentViewController = host
        if self.window == nil {
            window.setContentSize(NSSize(width: 980, height: 700))
            window.center()
            window.setFrameAutosaveName("MarginSettings")
        } else {
            window.setFrame(frame, display: false)
        }
        self.window = window
    }

    public func windowWillClose(_ notification: Notification) {
        // A dialog opened from settings goes with the window.
        if workspace?.dialog != nil { workspace?.dialog = nil }
    }
}
