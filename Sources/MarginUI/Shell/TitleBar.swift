import SwiftUI

/// 44 px title bar: space for the traffic lights, back/forward, sidebar toggle, tabs, `+`,
/// inspector tabs (when open) and the inspector toggle.
struct TitleBar: View {
    @Bindable var model: AppModel
    let inspector: InspectorContent?
    /// Width of the expanded sidebar; the tabs start at its divider.
    var sidebarWidth: CGFloat = 220
    var onNewTab: () -> Void = {}

    static let height: CGFloat = 44
    /// Traffic lights, back/forward and the sidebar toggle need this much from the window edge.
    static let controlsWidth: CGFloat = 178
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var inspectorShown: Bool { model.inspectorOpen && inspector != nil }

    var body: some View {
        HStack(spacing: 0) {
            // Over the rail and sidebar: traffic lights (positioned by `WindowConfigurator`),
            // back/forward and the sidebar toggle. Ends at the sidebar divider.
            HStack(spacing: 18) {
                Color.clear.frame(width: 52, height: 12)
                HStack(spacing: 10) {
                    Icon("arrow_back", size: 18, color: MarginColor.textSecondary)
                    Icon("arrow_forward", size: 18, color: MarginColor.textDisabled)
                    ChromeButton(icon: "side_navigation", help: "Toggle sidebar (⌥⌘S)") {
                        withAnimation(Shell.panelAnimation(reduceMotion)) { model.toggleSidebar() }
                    }
                }
            }
            .padding(.leading, 16)
            .frame(width: model.sidebarCollapsed ? Self.controlsWidth
                                                 : max(Self.controlsWidth, Shell.railWidth + sidebarWidth),
                   alignment: .leading)

            // Between the dividers: only the tabs.
            TabStrip(model: model, onNewTab: onNewTab)

            // Over the inspector: its tab icons and the toggle; without it just the toggle.
            HStack(spacing: 0) {
                if inspectorShown, let inspector {
                    InspectorTabBar(model: model, tabs: inspector.tabs)
                    Spacer(minLength: 0)
                }
                ChromeButton(icon: "dock_to_left", help: "Toggle inspector (⌥⌘I)") {
                    withAnimation(Shell.panelAnimation(reduceMotion)) { model.toggleInspector() }
                }
                .padding(.trailing, 12)
                .padding(.leading, inspectorShown ? 0 : 12)
            }
            // The card ends 8 px before the window edge, so the zone is the inspector plus that inset.
            .frame(width: inspectorShown ? (model.inspectorWidth ?? Shell.inspectorWidth) + Shell.cardInset : nil,
                   alignment: .leading)
        }
        .frame(height: Self.height)
        .background { WindowDragArea() }
    }
}

/// Small icon button in the chrome: 18 px icon, hover `#E9EAEE`, radius 6.
struct ChromeButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 18, color: MarginColor.textSecondary)
                .padding(3)
                .background(hovered ? MarginColor.borderSubtle : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// Tabs: 188 px wide, top radius 9, course dot, close button on the active/hovered tab,
/// drag horizontally to reorder.
private struct TabStrip: View {
    @Bindable var model: AppModel
    let onNewTab: () -> Void
    @State private var dragging: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var dragFrom = 0

    private static let maxWidth: CGFloat = 188
    private static let minWidth: CGFloat = 72
    private static let spacing: CGFloat = 2
    // Room for the active tab's left foot so it never crosses the sidebar divider.
    private static let leading: CGFloat = 12
    private static let plusWidth: CGFloat = 30

    /// Tabs are 188 px as in the mockup and shrink evenly when they do not fit (like a browser).
    private func tabWidth(available: CGFloat) -> CGFloat {
        let count = CGFloat(max(model.tabs.count, 1))
        let room = available - Self.leading - Self.plusWidth - Self.spacing * count
        return min(Self.maxWidth, max(Self.minWidth, (room / count).rounded(.down)))
    }

    var body: some View {
        GeometryReader { geo in
            let width = tabWidth(available: geo.size.width)
            let step = width + Self.spacing
            let target = TabReorder.target(from: dragFrom, translation: dragOffset, step: step,
                                           count: model.tabs.count)
            HStack(alignment: .bottom, spacing: Self.spacing) {
                ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                    let active = tab.id == model.activeTabID
                    let nextActive = index + 1 < model.tabs.count && model.tabs[index + 1].id == model.activeTabID
                    TabItem(
                        tab: tab, isActive: active,
                        showSeparator: !active && !nextActive && index < model.tabs.count - 1,
                        onClose: { withAnimation(.easeOut(duration: 0.16)) { model.close(tab.id) } }
                    )
                    .frame(width: width)
                    // The dragged tab follows the pointer; the others slide aside live (like Chrome).
                    .offset(x: dragging == tab.id
                        ? dragOffset
                        : dragging == nil ? 0 : TabReorder.shift(index: index, from: dragFrom, to: target, step: step))
                    .animation(dragging == tab.id ? nil : .easeOut(duration: 0.16), value: target)
                    .zIndex(dragging == tab.id ? 2 : active ? 1 : 0)
                    .onTapGesture { model.select(tab.id) }
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                if dragging == nil {
                                    dragging = tab.id
                                    dragFrom = index
                                    model.select(tab.id)
                                }
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                let to = TabReorder.target(from: dragFrom, translation: value.translation.width,
                                                           step: step, count: model.tabs.count)
                                // Layout moves and offsets reset in one animation: the neighbours'
                                // two changes cancel out (they stay put), the dragged tab settles.
                                withAnimation(.easeOut(duration: 0.16)) {
                                    model.move(tab.id, to: to)
                                    dragging = nil
                                    dragOffset = 0
                                }
                            }
                    )
                }
                ChromeButton(icon: "add", help: "New tab (⌘T)", action: onNewTab)
                    .frame(width: Self.plusWidth, height: 30)
                    .padding(.bottom, 4)
            }
            .padding(.leading, Self.leading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        // Never wider than the space it is given, so the bar cannot push the window content.
        // Clip sideways only: the active tab reaches 2 px below the bar to merge with the card.
        .frame(minWidth: 0, maxWidth: .infinity)
        .mask(Rectangle().padding(.bottom, -3))
        // Clicking or dragging a tab of an inactive window acts immediately (like Chrome).
        .allowsWindowActivationEvents(true)

    }
}

private struct TabItem: View {
    let tab: ShellTab
    let isActive: Bool
    let showSeparator: Bool
    let onClose: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hexString: tab.dot)).frame(width: 7, height: 7)
            Text(tab.title)
                .marginFont(MarginTextSize.sm)
                .foregroundStyle(isActive ? MarginColor.ink : MarginColor.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isActive || hovered {
                TabCloseButton(action: onClose)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(height: isActive ? 37 : 32)
        .background {
            if isActive {
                // Chrome-style: the tab flows into the content card through concave feet, with no
                // edge or separator between them. Feet reach `ChromeTabShape.foot` past the frame.
                let shape = ChromeTabShape()
                shape.fill(MarginColor.surface)
                    .padding(.horizontal, -ChromeTabShape.foot)
                shape.outline.stroke(MarginColor.borderSubtle, lineWidth: 1)
                    .padding(.horizontal, -ChromeTabShape.foot)
            } else if hovered {
                RoundedRectangle(cornerRadius: MarginRadius.sm).fill(MarginColor.tabHover)
            }
        }
        .overlay(alignment: .trailing) {
            if showSeparator && !hovered {
                MarginDivider(.vertical, color: MarginColor.border).frame(height: 14).offset(x: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        // The active tab overlaps the card's top border by 1 px so the two read as one surface.
        .padding(.bottom, isActive ? -1 : 4)
    }
}

/// Close „×“ of a tab: a 22 px round target with a hover fill (Chrome). The tap is attached to the
/// button itself so it wins over the tab's select tap and reorder drag.
private struct TabCloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Icon("close", size: 14, color: hovered ? MarginColor.ink : MarginColor.textSecondary)
            .frame(width: 22, height: 22)
            .background(hovered ? MarginColor.borderSubtle : .clear, in: Circle())
            .contentShape(Circle())
            .onHover { hovered = $0 }
            .highPriorityGesture(TapGesture().onEnded(action))
            .help("Close tab (⌘W)")
            .accessibilityElement()
            .accessibilityLabel("Close tab")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// Active tab outline as in Chrome: rounded top corners and concave feet that curve out into the
/// content card's top edge. The rect passed in includes the feet (`foot` on each side).
struct ChromeTabShape: Shape {
    static let foot: CGFloat = 12
    static let radius: CGFloat = 10

    /// Closed shape for the fill; it reaches 1 px below the frame to cover the card's top border.
    func path(in rect: CGRect) -> Path {
        var p = outlinePath(in: rect)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 1))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY + 1))
        p.closeSubpath()
        return p
    }

    /// Open outline without the bottom edge, for the stroke.
    var outline: some Shape { Outline() }

    private struct Outline: Shape {
        func path(in rect: CGRect) -> Path { ChromeTabShape().outlinePath(in: rect) }
    }

    func outlinePath(in rect: CGRect) -> Path {
        let f = Self.foot, r = Self.radius
        // Stroke centre sits on the card border line (0.5 px above the bottom).
        let bottom = rect.maxY - 0.5
        let left = rect.minX + f, right = rect.maxX - f
        // Circular arcs tangent to each edge, so the curves flow without kinks (as in Chrome).
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: bottom))
        p.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: rect.minY), radius: f)
        p.addArc(tangent1End: CGPoint(x: left, y: rect.minY), tangent2End: CGPoint(x: right, y: rect.minY), radius: r)
        p.addArc(tangent1End: CGPoint(x: right, y: rect.minY), tangent2End: CGPoint(x: right, y: bottom), radius: r)
        p.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: rect.maxX, y: bottom), radius: f)
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        return p
    }
}

/// Inspector tab icons (32×30, radius 7) sitting in the title bar above the inspector.
private struct InspectorTabBar: View {
    @Bindable var model: AppModel
    let tabs: [InspectorTab]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                let current = tabs.contains(model.inspectorTab) ? model.inspectorTab : tabs.first
                InspectorTabButton(tab: tab, isOn: tab == current) { model.inspectorTab = tab }
            }
        }
        .padding(.leading, 4)
    }
}

private struct InspectorTabButton: View {
    let tab: InspectorTab
    let isOn: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Icon(tab.icon, size: 18, weight: isOn ? .bold : .regular,
                 color: isOn ? MarginColor.ink : MarginColor.textSecondary)
                .frame(width: 32, height: 30)
                .background(isOn ? MarginColor.canvas : (hovered ? Color(hex: 0xECEDF0) : .clear),
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(tab.label)
    }
}

/// Index math for dragging a tab: where it would land and how far the others slide meanwhile.
enum TabReorder {
    /// Landing index for a tab dragged from `from` by `translation`, clamped to the strip.
    static func target(from: Int, translation: CGFloat, step: CGFloat, count: Int) -> Int {
        guard step > 0, count > 0 else { return from }
        let delta = Int((translation / step).rounded())
        return min(max(from + delta, 0), count - 1)
    }

    /// Offset of the tab at `index` while another tab is dragged from `from` towards `to`.
    static func shift(index: Int, from: Int, to: Int, step: CGFloat) -> CGFloat {
        if from < to, index > from, index <= to { return -step }
        if to < from, index >= to, index < from { return step }
        return 0
    }
}
