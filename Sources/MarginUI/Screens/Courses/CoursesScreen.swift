import MarginCore
import SwiftUI

/// Courses home in the shell (1a / 1b): the sidebar switches Cards ↔ Timetable (title menu),
/// filters by faculty or picks a week; a card opens its course in a tab, a block its class.
public struct CoursesScreen: View {
    @State private var shell: AppModel
    @State private var model: CoursesOverviewModel

    public init(env: AppEnvironment, mode: CoursesOverviewModel.Mode = .grid, shell: AppModel? = nil) {
        _model = State(initialValue: CoursesOverviewModel(env: env, mode: mode))
        _shell = State(initialValue: shell ?? AppModel(tabs: [ShellTab(title: "Courses", route: "courses")]))
    }

    public var body: some View {
        MarginShell(model: shell, rail: rail, sidebar: sidebar) {
            content(for: shell.activeTab?.route)
        }
        .task { await model.load() }
        .task { await model.observe() }
    }

    /// The page of the active tab. Course and class pages come in M4 / M6; until then a placeholder.
    @ViewBuilder
    private func content(for route: String?) -> some View {
        if let route, route.hasPrefix("course/"), let course = model.course(id: String(route.dropFirst(7))) {
            PendingPage(course: course, title: course.name, detail: "\(course.code) · course page (2c) comes in M4")
        } else if let route, route.hasPrefix("session/"), let tab = shell.activeTab {
            let courseID = model.cards.first { route.dropFirst(8).hasPrefix($0.id + "-") }?.course
            PendingPage(course: courseID, title: tab.title, detail: "Lecture note (3a) comes in M6")
        } else {
            switch model.mode {
            case .grid:
                CoursesGridView(model: model, onOpen: open(course:))
            case .timetable:
                TimetableView(model: model, onOpen: open(session:))
            }
        }
    }

    private func open(course: Course) {
        shell.show(ShellTab(title: course.name, dot: course.style.dot, route: "course/\(course.id)"))
    }

    private func open(session: SessionOccurrence) {
        let dot = model.course(id: session.session.courseID)?.style.dot ?? "#9A9DA6"
        shell.show(ShellTab(title: model.title(of: session), dot: dot, route: "session/\(session.id)"))
    }

    private var rail: RailContent {
        RailContent(active: "home",
                    courses: model.cards.map { ($0.course.id, $0.course.name, $0.course.style) },
                    initials: "AK")
    }

    // MARK: Sidebar (`Sidebar.dc.html`, views `grid` and `timetable`)

    private var sidebar: SidebarContent {
        let model = self.model
        let views = [
            SidebarContent.Item("Cards", isOn: model.mode == .grid) { model.mode = .grid },
            SidebarContent.Item("Timetable", isOn: model.mode == .timetable) { model.mode = .timetable },
        ]
        switch model.mode {
        case .grid:
            // TODO(M10-16.U): „New course“ opens the New course dialog (1g).
            return SidebarContent(title: "Courses", actionTitle: "New course",
                                  sections: [groupsSection, semestersSection], views: views)
        case .timetable:
            // TODO(M10-14.U): „Add session“ opens the session editor.
            return SidebarContent(title: "Timetable", actionTitle: "Add session",
                                  sections: [weeksSection, showSection], views: views)
        }
    }

    private var groupsSection: SidebarContent.Section {
        let model = self.model
        var items = [SidebarContent.Item("All courses", icon: "grid_view", count: "\(model.cards.count)",
                                         isOn: model.faculty == nil) { model.faculty = nil }]
        for faculty in model.faculties {
            let courses = model.cards.filter { $0.course.faculty == faculty }
            items.append(.init(faculty, icon: courses.first?.course.style.icon ?? "school",
                               count: "\(courses.count)", isOn: model.faculty == faculty) { model.faculty = faculty })
        }
        return .init("Groups", items)
    }

    private var semestersSection: SidebarContent.Section {
        let current = model.semester?.id
        let items = model.semesters.reversed().map { semester in
            let meta: String
            if semester.id == current, let week = model.currentWeek {
                meta = "Current · week \(week) of \(semester.weekCount)"
            } else {
                meta = semester.isArchived ? "Archived" : (semester.id == current ? "Current" : "")
            }
            // TODO(M11-04.U): open a past semester read-only (1f).
            return SidebarContent.Item(semester.name, icon: semester.isArchived ? "inventory_2" : "school",
                                       meta: meta.isEmpty ? nil : meta, isOn: false)
        }
        return .init("Semesters", items)
    }

    private var weeksSection: SidebarContent.Section {
        let model = self.model
        guard let semester = model.semester else { return .init("Weeks", []) }
        let anchor = model.currentWeek ?? model.week
        let weeks = (anchor - 1...anchor + 2).filter { $0 >= 1 && $0 <= semester.weekCount }
        let items = weeks.map { week in
            let isBreak = semester.breakWeeks.contains(week)
            var meta = isBreak ? "Reading week" : model.range(ofWeek: week)
            if week == model.currentWeek { meta += " · now" }
            return SidebarContent.Item("Week \(week)", icon: "date_range", meta: meta, isOn: week == model.week) {
                Task { await model.showWeek(week) }
            }
        }
        return .init("Weeks", items)
    }

    private var showSection: SidebarContent.Section {
        let model = self.model
        let items = CoursesOverviewModel.KindGroup.allCases.map { group in
            let shown = !model.hiddenKinds.contains(group)
            return SidebarContent.Item(group.title, icon: shown ? "check_box" : "check_box_outline_blank",
                                       count: "\(model.count(of: group))") { model.toggle(group) }
        }
        return .init("Show", items)
    }
}

/// Stand-in for pages that later milestones build, so an opened tab shows what it is.
private struct PendingPage: View {
    let course: Course?
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 14) {
            if let course { CourseTile(style: course.style, size: 52) }
            Text(title).marginFont(MarginTextSize.lg, .semibold)
            Text(detail).marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
