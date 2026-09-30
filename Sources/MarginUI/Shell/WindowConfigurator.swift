import AppKit
import SwiftUI

/// Makes the hosting window chrome-less (transparent title bar, full-size content) and puts the
/// traffic lights where the mockup has them: 16 px from the left, centred in the 44 px bar.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }
    func updateNSView(_ nsView: ConfiguratorView, context: Context) {}

    final class ConfiguratorView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            // AppKit would turn any drag in the title bar area into a window move, stealing tab
            // drags. The window moves only from `WindowDragArea` (empty parts of the bar).
            window.isMovable = false
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in MainActor.assumeIsolated { self?.layoutTrafficLights() }
                })
            }
            layoutTrafficLights()
        }

        private func layoutTrafficLights() {
            guard let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let container = close.superview else { return }
            // The system title bar keeps its own height (it must not grow over the tab strip, or
            // it would take drags meant for the tabs); only the buttons move, centred at y = 22.
            let barCentre = TitleBar.height / 2
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (i, type) in buttons.enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                // 12 px lights, 8 px apart; the button frame is slightly larger than the light.
                let inset = (button.frame.width - 12) / 2
                let y = container.isFlipped
                    ? barCentre - button.frame.height / 2
                    : container.bounds.height - barCentre - button.frame.height / 2
                button.setFrameOrigin(NSPoint(x: 16 - inset + CGFloat(i) * 20, y: y))
            }
        }
    }
}

/// Empty title bar area: drag moves the window, double-click zooms (like a system title bar).
/// The window itself is not movable (see `WindowConfigurator`), so drags that start on tabs reach
/// the tab reorder gesture instead of moving the window.
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .onTapGesture(count: 2) { NSApp.keyWindow?.performZoom(nil) }
            .allowsWindowActivationEvents(true)
    }
}
