import SwiftUI

/// 44 px title bar: space for the traffic lights, back/forward, sidebar toggle, tabs, `+`,
/// inspector tabs (when open) and the inspector toggle.
struct TitleBar: View {
    @Bindable var model: AppModel
    let inspector: InspectorContent?
    var onNewTab: () -> Void = {}

    static let height: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 18) {
            // Traffic lights: 3 × 12 px with 8 px gaps, positioned by `WindowConfigurator`.
            Color.clear.frame(width: 52, height: 12)
            HStack(spacing: 10) {
                Icon("arrow_back", size: 18, color: MarginColor.textSecondary)
                Icon("arrow_forward", size: 18, color: MarginColor.textDisabled)
                ChromeButton(icon: "side_navigation", help: "Toggle sidebar (⌥⌘S)") {
                    withAnimation(Shell.panelAnimation(reduceMotion)) { model.toggleSidebar() }
                }
            }
            TabStrip(model: model, onNewTab: onNewTab)
            if model.inspectorOpen, let inspector {
                InspectorTabBar(model: model, tabs: inspector.tabs)
                    // Aligned with the inspector: its left edge sits at W − 8 − 300.
                    .frame(width: Shell.inspectorWidth - 30, alignment: .leading)
            }
        }
        .padding(.leading, 16)
        // Keep clear of the inspector toggle (12 + 24); with the inspector open the tab bar ends
        // 30 px before the inspector's right edge, as in `Inspector.dc.html`.
        .padding(.trailing, model.inspectorOpen && inspector != nil ? 30 + 8 : 12 + 24 + 18)
        .overlay(alignment: .trailing) {
            ChromeButton(icon: "dock_to_left", help: "Toggle inspector (⌥⌘I)") {
                withAnimation(Shell.panelAnimation(reduceMotion)) { model.toggleInspector() }
            }
            .padding(.trailing, 12)
        }
        .frame(height: Self.height)
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

    private static let maxWidth: CGFloat = 188
    private static let minWidth: CGFloat = 72
    private static let spacing: CGFloat = 2
    private static let leading: CGFloat = 10
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
                    .offset(x: dragging == tab.id ? dragOffset : 0)
                    .zIndex(dragging == tab.id ? 2 : active ? 1 : 0)
                    .onTapGesture { model.select(tab.id) }
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                dragging = tab.id
                                dragOffset = value.translation.width
                                model.select(tab.id)
                            }
                            .onEnded { value in
                                let delta = Int((value.translation.width / (width + Self.spacing)).rounded())
                                withAnimation(.easeOut(duration: 0.18)) {
                                    model.move(tab.id, to: index + delta)
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
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
    }
}

private struct TabItem: View {
    let tab: ShellTab
    let isActive: Bool
    let showSeparator: Bool
    let onClose: () -> Void
    @State private var hovered = false

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9)
        HStack(spacing: 8) {
            Circle().fill(Color(hexString: tab.dot)).frame(width: 7, height: 7)
            Text(tab.title)
                .marginFont(MarginTextSize.sm)
                .foregroundStyle(isActive ? MarginColor.ink : MarginColor.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isActive || hovered {
                Button(action: onClose) {
                    Icon("close", size: 16, color: MarginColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Close tab (⌘W)")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: isActive ? 37 : 32)
        .background {
            if isActive {
                shape.fill(MarginColor.surface)
                shape.stroke(MarginColor.borderSubtle)
                // Hide the bottom edge so the active tab merges with the content card.
                MarginColor.surface.frame(height: 2).frame(maxHeight: .infinity, alignment: .bottom).offset(y: 1)
            } else if hovered {
                shape.fill(MarginColor.tabHover)
            }
        }
        .overlay(alignment: .trailing) {
            if showSeparator && !hovered {
                MarginDivider(.vertical, color: MarginColor.border).frame(height: 14).offset(x: 2)
            }
        }
        .contentShape(shape)
        .onHover { hovered = $0 }
        .padding(.bottom, isActive ? -1 : 4)
    }
}

/// Inspector tab icons (32×30, radius 7) sitting in the title bar above the inspector.
private struct InspectorTabBar: View {
    @Bindable var model: AppModel
    let tabs: [InspectorTab]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                InspectorTabButton(tab: tab, isOn: tab == model.inspectorTab) { model.inspectorTab = tab }
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
