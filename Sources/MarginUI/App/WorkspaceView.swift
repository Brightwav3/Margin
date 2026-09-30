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
        .overlay {
            if workspace.capture.isOpen {
                ZStack(alignment: .top) {
                    Color(hex: 0x1C1E26, opacity: 0.32).ignoresSafeArea()
                        .onTapGesture { workspace.capture.close() }
                    QuickCaptureView(model: workspace.capture).padding(.top, 170)
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { ToastView(toast: workspace.toast).padding(.bottom, 28) }
        .background {
            Button("Quick capture") { workspace.capture.open() }
                .keyboardShortcut(.space, modifiers: [.control, .option])
                .opacity(0).allowsHitTesting(false)
        }
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
        case .note, .draft:
            return noteChrome(route)
        case .inbox:
            var chrome = tasksChrome(.today)
            chrome.sidebar.title = "Inbox"
            chrome.sidebar.actionTitle = "Capture"
            chrome.sidebar.actionIcon = "bolt"
            chrome.sidebar.sections[0].items = chrome.sidebar.sections[0].items.map { var i = $0; i.isOn = i.title == "Inbox"; return i }
            chrome.sidebar.sections.removeLast()
            return chrome
        case .today:
            return tasksChrome(.today)
        case .upcoming:
            return tasksChrome(.upcoming)
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
        case .note, .draft:
            NoteEditorView(model: editorModel(route))
        case .inbox:
            InboxView(model: inboxModel())
        case .today:
            TasksView(model: tasksModel(.today))
        case .upcoming:
            TasksView(model: tasksModel(.upcoming))
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
