import MarginPlatform
import MarginUI
import SwiftUI

@main
struct MarginApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let requestedScreen = MarginScreens.requestedID()
    private let showsGallery = ProcessInfo.processInfo.arguments.contains("--gallery")

    var body: some Scene {
        WindowGroup {
            if let id = requestedScreen, let screen = MarginScreens.screen(id: id) {
                // `--screen <id>`: one gallery screen at mockup size, on sample data.
                screen.view()
                    .frame(minWidth: 820, idealWidth: MarginScreens.size.width, maxWidth: .infinity,
                           minHeight: 560, idealHeight: MarginScreens.size.height, maxHeight: .infinity)
            } else if showsGallery {
                ScreenGallery()
            } else {
                AppRootView(state: delegate.state)
                    .task { delegate.state.start() }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: MarginScreens.size.width, height: MarginScreens.size.height)
        .windowResizability(.contentMinSize)
        .commands { MarginCommands(state: delegate.state) }
    }
}

/// Owns the app state so the global hotkey and the menu reach it, and closes the vault on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Margin has its own tabs; the system window tabs (View › Show Tab Bar) would compete.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await state.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Clicking the Dock icon with no window open brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
}
