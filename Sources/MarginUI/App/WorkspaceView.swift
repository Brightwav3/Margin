import MarginCore
import SwiftUI

/// The app window: the shell around the page of the active tab, plus dialogs and toasts.
public struct WorkspaceView: View {
    @State private var workspace: Workspace

    public init(workspace: Workspace) {
        _workspace = State(initialValue: workspace)
    }

    public init(env: AppEnvironment, start: Route = .courses, mode: CoursesOverviewModel.Mode = .grid,
                inspectorOpen: Bool = false) {
        let workspace = Workspace(env: env, start: start)
        workspace.courses.mode = mode
        workspace.shell.inspectorOpen = inspectorOpen
        _workspace = State(initialValue: workspace)
    }

    public var body: some View {
        let route = workspace.route
        let chrome = workspace.chrome(for: route)
        MarginShell(model: workspace.shell, rail: workspace.rail, sidebar: chrome.sidebar,
                    inspector: chrome.inspector,
                    onRail: { workspace.railSelect($0) },
                    onNewTab: { workspace.shell.open(ShellTab(title: "Search", route: Route.search("").key)) }) {
            workspace.page(for: route)
                .id(route.key)
        }
        .overlay(alignment: .bottom) { ToastView(toast: workspace.toast).padding(.bottom, 28) }
        .task {
            await workspace.courses.load()
            workspace.refreshTabTitles()
        }
        .task { await workspace.courses.observe() }
        .task { await workspace.refreshInbox() }
        .environment(workspace)
    }
}

/// Sidebar and inspector of a page.
struct PageChrome {
    var sidebar: SidebarContent
    var inspector: InspectorContent?
}

extension Workspace {
    func chrome(for route: Route) -> PageChrome {
        switch route {
        case .courses:
            return PageChrome(sidebar: coursesSidebar, inspector: nil)
        case .course(let id):
            return courseChrome(id)
        default:
            return PageChrome(sidebar: coursesSidebar, inspector: nil)
        }
    }

    @ViewBuilder
    func page(for route: Route) -> some View {
        switch route {
        case .courses:
            switch courses.mode {
            case .grid:
                CoursesGridView(model: courses, onOpen: { [weak self] in self?.open(course: $0) },
                                onNewCourse: { [weak self] in self?.dialog = .newCourse })
            case .timetable:
                TimetableView(model: courses, onOpen: { [weak self] in self?.open(session: $0) })
            }
        case .course(let id):
            CourseView(model: courseModel(id))
        default:
            PendingPage(course: nil, title: Self.title(of: route), detail: "Coming up next")
        }
    }
}

/// Bottom toast (popups 1i).
struct ToastView: View {
    let toast: Workspace.Toast?

    var body: some View {
        ZStack {
            if let toast {
                HStack(spacing: 10) {
                    Icon(toast.icon, size: 18, color: toast.isError ? MarginColor.due : .white)
                    Text(toast.text).marginFont(MarginTextSize.sm).foregroundStyle(.white).lineLimit(2)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(MarginColor.ink, in: RoundedRectangle(cornerRadius: MarginRadius.md))
                .marginShadow(.popover)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
    }
}
