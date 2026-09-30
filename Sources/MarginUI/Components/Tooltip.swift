import AppKit
import SwiftUI

/// Tooltips and hover cards (Margin Menus 3a–3h, specs 4a): drawn in a borderless child window so
/// no parent clip cuts them off. Tooltip: `#1C1E26`, 13 px, radius 7, 8 px arrow, after 500 ms,
/// hides on click. Hover card: menu surface, radius 12, after 300 ms, stays while the pointer is on it.
public enum TooltipPlacement: Sendable { case top, bottom, leading, trailing }

extension View {
    /// 3a label with an optional shortcut („Search ⌘K“); a trailing „(⌘K)“ in `title` is split off.
    public func marginTooltip(_ title: String, shortcut: String? = nil, placement: TooltipPlacement = .bottom) -> some View {
        let (label, key) = TooltipText.split(title, shortcut)
        return modifier(TooltipModifier(placement: placement, delay: 0.5, isCard: false) {
            AnyView(TooltipBubble(title: label, shortcut: key))
        })
    }

    /// 3b / 3c / 3d: a title with a second line of explanation.
    public func marginTooltip(_ title: String, detail: String?, placement: TooltipPlacement = .bottom) -> some View {
        modifier(TooltipModifier(placement: placement, delay: 0.5, isCard: false) {
            AnyView(TooltipBubble(title: title, detail: detail))
        })
    }

    /// 3e hover card: any content on the menu surface.
    func marginHoverCard<Card: View>(placement: TooltipPlacement = .trailing, @ViewBuilder _ card: @escaping () -> Card) -> some View {
        modifier(TooltipModifier(placement: placement, delay: 0.3, isCard: true) { AnyView(card()) })
    }
}

enum TooltipText {
    /// „Toggle sidebar (⌥⌘S)“ → („Toggle sidebar“, „⌥⌘S“).
    static func split(_ title: String, _ shortcut: String?) -> (String, String?) {
        if let shortcut { return (title, shortcut) }
        guard title.hasSuffix(")"), let open = title.range(of: " (", options: .backwards) else { return (title, nil) }
        let key = String(title[open.upperBound..<title.index(before: title.endIndex)])
        let symbols = CharacterSet(charactersIn: "⌘⌥⌃⇧↵⎋⇥←→↑↓,.\\/;`[]+−0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ Space")
        guard key.unicodeScalars.allSatisfy({ symbols.contains($0) }) else { return (title, nil) }
        return (String(title[..<open.lowerBound]), key)
    }
}

/// Dark bubble: label and shortcut chip, or title and grey explanation.
struct TooltipBubble: View {
    var title: String
    var shortcut: String?
    var detail: String?
    var tone: Color = MarginColor.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title).font(.margin(13, detail == nil ? .regular : .semibold)).foregroundStyle(.white)
                if let shortcut {
                    Text(shortcut).font(.margin(11)).foregroundStyle(Color(hex: 0xC4C7CF))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color(hex: 0x33363F), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            if let detail {
                Text(detail).font(.margin(13)).foregroundStyle(Color(hex: 0xC4C7CF)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, shortcut == nil ? 10 : 7)
        .padding(.vertical, 6)
        .frame(maxWidth: detail == nil ? nil : 260, alignment: .leading)
        .background(tone, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Hover-card surface (4a: menu surface with radius 12).
struct HoverCardSurface<Content: View>: View {
    var width: CGFloat = 290
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(width: width, alignment: .leading)
            .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MarginColor.borderCard) }
    }
}

private struct TooltipModifier: ViewModifier {
    let placement: TooltipPlacement
    let delay: TimeInterval
    let isCard: Bool
    let content: () -> AnyView

    func body(content view: Content) -> some View {
        view.overlay { TooltipAnchor(placement: placement, delay: delay, isCard: isCard, content: content) }
    }
}

/// Invisible AppKit view over the target: tracks the pointer without taking clicks.
private struct TooltipAnchor: NSViewRepresentable {
    let placement: TooltipPlacement
    let delay: TimeInterval
    let isCard: Bool
    let content: () -> AnyView

    func makeNSView(context: Context) -> AnchorView {
        let v = AnchorView()
        v.configure(self)
        return v
    }

    func updateNSView(_ v: AnchorView, context: Context) { v.configure(self) }

    static func dismantleNSView(_ v: AnchorView, coordinator: ()) { v.cancel() }

    final class AnchorView: NSView {
        private var spec: TooltipAnchor?
        private var tracking: NSTrackingArea?
        private var timer: Timer?
        private var clickMonitor: Any?

        func configure(_ spec: TooltipAnchor) { self.spec = spec }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                   owner: self, userInfo: nil)
            addTrackingArea(t)
            tracking = t
        }

        override func mouseEntered(with event: NSEvent) {
            guard let spec else { return }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: spec.delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.show() }
            }
        }

        override func mouseExited(with event: NSEvent) {
            timer?.invalidate()
            timer = nil
            TooltipWindow.shared.hide(owner: self, grace: spec?.isCard == true ? 0.2 : 0)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { cancel() }
        }

        func cancel() {
            timer?.invalidate()
            timer = nil
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            TooltipWindow.shared.hide(owner: self, grace: 0)
        }

        private func show() {
            guard let spec, let window, !isHiddenOrHasHiddenAncestor else { return }
            let rect = window.convertToScreen(convert(bounds, to: nil))
            TooltipWindow.shared.show(spec.content(), at: rect, placement: spec.placement, isCard: spec.isCard,
                                      owner: self, parent: window)
            if !spec.isCard, clickMonitor == nil {
                // Tooltips hide on click (4a).
                clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
                    if let self { TooltipWindow.shared.hide(owner: self, grace: 0) }
                    return e
                }
            }
        }

        deinit {
            MainActor.assumeIsolated {
                if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            }
        }
    }
}

/// The one window that shows the current tooltip or hover card.
@MainActor
final class TooltipWindow {
    static let shared = TooltipWindow()
    private let panel: NSPanel
    /// Measures content outside any window; the shown view is a fresh host added after the panel is placed.
    private let measure = NSHostingView(rootView: AnyView(EmptyView()))
    private let container = NSView()
    private weak var owner: NSView?
    private var hideTimer: Timer?
    private var hovering = false

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = container
    }

    func show(_ content: AnyView, at anchor: NSRect, placement: TooltipPlacement, isCard: Bool, owner: NSView, parent: NSWindow) {
        hideTimer?.invalidate()
        self.owner = owner
        let gap: CGFloat = isCard ? 6 : 8
        let view = AnyView(
            content
                .onHover { [weak self] inside in self?.hovering = inside; if !inside { self?.hide(owner: owner, grace: 0.15) } }
        )
        panel.ignoresMouseEvents = !isCard
        // A hosting view that is measured or moved while in this small window re-enters constraint
        // updates until AppKit throws; so measure off-window, place the panel, then add the view.
        measure.rootView = view
        let size = measure.fittingSize
        measure.rootView = AnyView(EmptyView())
        guard size.width > 0, size.height > 0 else { return }
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var p = placement
        // Flip when there is no room (bottom near the Dock, trailing near the screen edge).
        if p == .bottom && anchor.minY - size.height - gap < screen.minY { p = .top }
        if p == .top && anchor.maxY + size.height + gap > screen.maxY { p = .bottom }
        if p == .trailing && anchor.maxX + size.width + gap > screen.maxX { p = .leading }
        var origin: NSPoint = switch p {
        case .bottom: NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
        case .top: NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        case .trailing: NSPoint(x: anchor.maxX + gap, y: isCard ? anchor.maxY - size.height : anchor.midY - size.height / 2)
        case .leading: NSPoint(x: anchor.minX - gap - size.width, y: isCard ? anchor.maxY - size.height : anchor.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        origin.y = min(max(origin.y, screen.minY + 4), screen.maxY - size.height - 4)
        container.subviews.forEach { $0.removeFromSuperview() }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        if panel.parent !== parent { panel.parent?.removeChildWindow(panel); parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide(owner: NSView, grace: TimeInterval) {
        guard self.owner === owner else { return }
        hideTimer?.invalidate()
        if grace == 0 { close(); return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: grace, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.hovering else { return }
                self.close()
            }
        }
    }

    private func close() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        container.subviews.forEach { $0.removeFromSuperview() }
        owner = nil
        hovering = false
    }
}
