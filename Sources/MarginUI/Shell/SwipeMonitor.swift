import AppKit
import SwiftUI

/// Two-finger horizontal swipe over a view (trackpad) or shift + wheel (mouse): one step per
/// gesture, as in `Sidebar.dc.html` (`onWheel`). Vertical scrolling passes through untouched.
struct HorizontalSwipe: NSViewRepresentable {
    /// −1 = previous page (fingers move right), +1 = next page (fingers move left).
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onSwipe = onSwipe
    }

    final class MonitorView: NSView {
        var onSwipe: (Int) -> Void = { _ in }
        private var monitor: Any?
        private var tracker = SwipeTracker()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // Read the event here (NSEvent is not Sendable) and hand plain values to the view.
                let input = SwipeTracker.Input(
                    dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                    began: event.phase.contains(.began),
                    ended: event.phase.contains(.ended) || event.phase.contains(.cancelled),
                    momentum: event.momentumPhase != [], hasPhase: event.phase != [] || event.momentumPhase != [],
                    natural: event.isDirectionInvertedFromDevice, time: event.timestamp
                )
                let windowNumber = event.windowNumber
                let location = event.locationInWindow
                let swallow = MainActor.assumeIsolated {
                    self?.handle(input, windowNumber: windowNumber, location: location) ?? false
                }
                return swallow ? nil : event
            }
        }

        // Clicks go to the SwiftUI content underneath; this view only watches scroll events.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// Returns true when the event belongs to this swipe and should not scroll anything else.
        private func handle(_ input: SwipeTracker.Input, windowNumber: Int, location: NSPoint) -> Bool {
            guard let window, window.windowNumber == windowNumber,
                  bounds.contains(convert(location, from: nil)) else { return false }
            let result = tracker.consume(input)
            if let step = result.step { onSwipe(step) }
            return result.swallow
        }
    }
}

/// Swipe recognition, separate from AppKit so it can be unit tested.
struct SwipeTracker {
    struct Input: Sendable {
        var dx: CGFloat
        var dy: CGFloat
        var began = false
        var ended = false
        var momentum = false
        /// Trackpad gestures have phases; a classic mouse wheel does not.
        var hasPhase = true
        /// Natural scrolling: `dx` follows the fingers.
        var natural = true
        var time: TimeInterval = 0
    }

    static let threshold: CGFloat = 30
    static let wheelLock: TimeInterval = 0.6

    private var accX: CGFloat = 0
    private var accY: CGFloat = 0
    private var fired = false
    private var lastWheelFire: TimeInterval = -.infinity

    /// Returns the page step to take (if any) and whether the event should be swallowed.
    mutating func consume(_ e: Input) -> (step: Int?, swallow: Bool) {
        if !e.hasPhase {
            // Mouse wheel (shift + wheel scrolls horizontally): one step, then a short lock.
            guard abs(e.dx) > abs(e.dy), abs(e.dx) > 0, e.time - lastWheelFire > Self.wheelLock else {
                return (nil, false)
            }
            lastWheelFire = e.time
            return (Self.step(fingerDX: fingerDX(e)), true)
        }
        if e.momentum { return (nil, fired) }
        if e.began { accX = 0; accY = 0; fired = false }
        accX += fingerDX(e)
        accY += e.dy
        var step: Int?
        if !fired, abs(accX) > Self.threshold, abs(accX) > abs(accY) * 1.5 {
            fired = true
            step = Self.step(fingerDX: accX)
        }
        let swallow = fired
        if e.ended { accX = 0; accY = 0; fired = false }
        return (step, swallow)
    }

    private func fingerDX(_ e: Input) -> CGFloat { e.natural ? e.dx : -e.dx }

    /// Fingers moving left reveal the page on the right (next), like paging in macOS.
    private static func step(fingerDX: CGFloat) -> Int { fingerDX < 0 ? 1 : -1 }
}
