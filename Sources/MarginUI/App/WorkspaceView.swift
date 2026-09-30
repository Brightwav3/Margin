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
        Group {
            if workspace.needsOnboarding {
                OnboardingView().overlay { DialogHost() }
            } else if let p = workspace.indexProgress, !p.isComplete, p.filesTotal > 0 {
                LoadingView(progress: p)
            } else {
                shell(route: route, chrome: chrome)
            }
        }
        .task {
            await workspace.courses.load()
            workspace.refreshTabTitles()
        }
        .task { await workspace.courses.observe() }
        .task { await workspace.refreshInbox() }
        .task { await workspace.watchIndex() }
        .task { await workspace.watchUpcomingClasses() }
        .task { workspace.applySettings() }
        .environment(workspace)
    }

    private func shell(route: Route, chrome: PageChrome) -> some View {
        MarginShell(model: workspace.shell, rail: workspace.rail, sidebar: chrome.sidebar,
                    inspector: chrome.inspector,
                    onRail: { workspace.railSelect($0) },
                    onNewTab: { workspace.openInNewTab = true; workspace.dialog = .palette }) {
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
        .overlay { DialogHost() }
        .animation(.easeOut(duration: 0.15), value: workspace.dialog)
        .overlay(alignment: .bottom) { ToastView(toast: workspace.toast).padding(.bottom, 28) }
        .overlay(alignment: .topTrailing) {
            if let soon = workspace.soonClass { ClassReminderCard(occurrence: soon).padding(.top, 56).padding(.trailing, 20) }
        }
        .background {
            Group {
                Button("Quick capture") { workspace.capture.open() }
                    .keyboardShortcut(.space, modifiers: [.command, .shift])
                Button("Command palette") { workspace.dialog = .palette }
                    .keyboardShortcut("k", modifiers: .command)
                Button("New note") { workspace.run(command: "new-note") }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Settings") { workspace.open(.settings) }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Search") { workspace.open(.search("")) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            .opacity(0).allowsHitTesting(false)
        }
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
        case .search, .grades, .archive, .settings:
            return PageChrome(sidebar: coursesSidebar, inspector: nil)
        case .inbox:
            var chrome = tasksChrome(.today)
            chrome.sidebar.title = "Inbox"
            chrome.sidebar.actionTitle = "Capture"
            chrome.sidebar.actionIcon = "bolt"
            chrome.sidebar.sections[0].items = chrome.sidebar.sections[0].items.map { var i = $0; i.isOn = i.title == "Inbox"; return i }
            chrome.sidebar.sections.removeLast()
            return chrome
        case .graph:
            let m = graphModel()
            let items = courses.cards.map { card in
                SidebarContent.Item(card.course.name, dot: card.course.style.dot, isOn: !m.hiddenCourses.contains(card.id)) {
                    if m.hiddenCourses.contains(card.id) { m.hiddenCourses.remove(card.id) } else { m.hiddenCourses.insert(card.id) }
                }
            }
            var views = [SidebarContent.Item("Whole semester", icon: "share", isOn: m.focus == nil) { m.focus = nil }]
            if let focus = m.focus {
                views.append(.init(m.graph.nodes.first { $0.id == focus }?.label ?? "Local graph", icon: "hub", isOn: true))
            }
            return PageChrome(sidebar: SidebarContent(title: "Graph", actionTitle: "Fit to screen", actionIcon: "center_focus_weak",
                                                      sections: [.init("Views", views), .init("Courses", items)],
                                                      onAction: { m.fit() }),
                              inspector: nil)
        case .today:
            return tasksChrome(.today)
        case .upcoming:
            return tasksChrome(.upcoming)
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
                TimetableView(model: courses, onOpen: { [weak self] in self?.open(session: $0) },
                              onReschedule: { [weak self] in self?.dialog = .session($0) })
            }
        case .course(let id):
            CourseView(model: courseModel(id))
        case .note, .draft:
            NoteEditorView(model: editorModel(route))
        case .search(let q):
            SearchView(model: searchModel(q))
        case .grades:
            GradesView(model: gradesModel())
        case .archive:
            ArchiveView()
        case .settings:
            SettingsView(model: settingsModel())
        case .inbox:
            InboxView(model: inboxModel())
        case .graph:
            GraphView(model: graphModel())
        case .today:
            TasksView(model: tasksModel(.today))
        case .upcoming:
            TasksView(model: tasksModel(.upcoming))
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
                        .accessibilityIdentifier("toast")
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

/// 1i Lecture reminder: „Cell Biology · in 10 min“ with Open note and Snooze.
struct ClassReminderCard: View {
    let occurrence: SessionOccurrence
    @Environment(Workspace.self) private var workspace

    var body: some View {
        let course = workspace.courses.course(id: occurrence.session.courseID)
        let minutes = occurrence.session.start.minutesSinceMidnight - workspace.env.clock.localNow.time.minutesSinceMidnight
        HStack(alignment: .top, spacing: 12) {
            if let course { CourseTile(style: course.style, size: 36) }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(course?.name ?? "Class") · in \(max(1, minutes)) min").marginFont(MarginTextSize.sm, .semibold)
                Text(workspace.courses.title(of: occurrence)).marginFont(MarginTextSize.sm)
                if let room = occurrence.session.room ?? course?.room {
                    Text(room).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textSecondary)
                }
                HStack(spacing: 8) {
                    MarginButton("Open note", kind: .primary, size: .small) {
                        workspace.open(session: occurrence); workspace.soonClass = nil
                    }
                    MarginButton("Snooze", size: .small) { workspace.soonClass = nil }
                }
                .padding(.top, 6)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.borderCard) }
        .marginShadow(.popover)
    }
}
