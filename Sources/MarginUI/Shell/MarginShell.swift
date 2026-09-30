import SwiftUI

enum Shell {
    static let railWidth: CGFloat = 56
    static let inspectorWidth: CGFloat = 300
    static let cardInset: CGFloat = 8

    /// Sidebar page slide: 420 ms `cubic-bezier(.2,.8,.2,1)`; none with Reduce Motion.
    static func slideAnimation(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.42)
    }

    /// Collapsing / expanding the side panels.
    static func panelAnimation(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)
    }
}

/// The app frame: title bar with tabs, rail, sidebar, content card and inspector
/// (`Sidebar.dc.html`, `Inspector.dc.html`, the `.dv-card` frame of every mockup).
public struct MarginShell<Content: View>: View {
    @Bindable var model: AppModel
    let rail: RailContent
    let sidebar: SidebarContent
    let inspector: InspectorContent?
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel, rail: RailContent, sidebar: SidebarContent, inspector: InspectorContent? = nil,
                @ViewBuilder content: () -> Content) {
        self.model = model
        self.rail = rail
        self.sidebar = sidebar
        self.inspector = inspector
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            MarginColor.sidebar

            HStack(spacing: 0) {
                Rail(content: rail)
                HStack(spacing: 0) {
                    if !model.sidebarCollapsed {
                        SidebarPanel(model: model, content: sidebar)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.inspectorOpen, let inspector {
                        InspectorPanel(model: model, content: inspector)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .background(MarginColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: MarginRadius.md))
                .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.borderSubtle) }
                .padding(.top, TitleBar.height)
                .padding([.bottom, .trailing], Shell.cardInset)
            }

            TitleBar(model: model, inspector: inspector, sidebarWidth: SidebarPanel.width(model: model, content: sidebar)) {
                model.open(ShellTab(title: "New tab"))
            }
        }
        .foregroundStyle(MarginColor.ink)
        .ignoresSafeArea()
        .background { WindowConfigurator() }
        .background {
            // Keyboard shortcuts (M1-07); hidden buttons keep them active without a menu.
            Group {
                Button("Toggle sidebar") {
                    withAnimation(Shell.panelAnimation(reduceMotion)) { model.toggleSidebar() }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Toggle inspector") {
                    withAnimation(Shell.panelAnimation(reduceMotion)) { model.toggleInspector() }
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                Button("Close tab") {
                    if let id = model.activeTabID { model.close(id) }
                }
                .keyboardShortcut("w", modifiers: .command)
                Button("New tab") { model.open(ShellTab(title: "New tab")) }
                    .keyboardShortcut("t", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
}
