import MarginCore
import Observation
import SwiftUI

/// One window: the services, the shell state (tabs, panels) and the screen models, kept per route
/// so switching tabs keeps each page's state.
@MainActor @Observable
public final class Workspace {
    public let env: AppEnvironment
    public let shell: AppModel
    public let courses: CoursesOverviewModel
    /// Short-lived message at the bottom of the window (1i toasts).
    public var toast: Toast?
    /// Modal dialog over the window (M10c).
    public var dialog: Dialog?

    public enum Dialog: Identifiable, Equatable {
        case newCourse
        case deleteNote(NoteSummary)
        case moveNote(NoteSummary)
        case grade(CourseID)
        case syllabus(CourseID)
        case share(NoteSummary)
        case archiveSemester(Semester)
        case session(SessionOccurrence)
        case history(NoteID)
        case palette

        public var id: String {
            switch self {
            case .newCourse: "newCourse"
            case .deleteNote(let n): "delete/\(n.id)"
            case .moveNote(let n): "move/\(n.id)"
            case .grade(let c): "grade/\(c)"
            case .syllabus(let c): "syllabus/\(c)"
            case .share(let n): "share/\(n.id)"
            case .archiveSemester(let s): "archive/\(s.id)"
            case .session(let o): "session/\(o.id)"
            case .history(let n): "history/\(n)"
            case .palette: "palette"
            }
        }
    }

    @ObservationIgnored private var models: [String: AnyObject] = [:]

    public init(env: AppEnvironment, shell: AppModel? = nil, start: Route = .courses) {
        self.env = env
        self.courses = CoursesOverviewModel(env: env)
        self.shell = shell ?? AppModel()
        if self.shell.tabs.isEmpty {
            self.shell.open(ShellTab(title: Self.title(of: start), dot: Self.grey, route: start.key))
        }
    }

    static let grey = "#9A9DA6"

    public var route: Route {
        shell.activeTab?.route.flatMap(Route.init(key:)) ?? .courses
    }

    /// The model of a route, created on first use.
    func model<M: AnyObject>(_ key: String, make: () -> M) -> M {
        if let existing = models[key] as? M { return existing }
        let made = make()
        models[key] = made
        return made
    }

    func forget(_ key: String) { models[key] = nil }

    // MARK: Navigation

    /// Shows `route` in its open tab or a new one.
    public func open(_ route: Route, title: String? = nil) {
        shell.show(ShellTab(title: title ?? Self.title(of: route), dot: dot(of: route), route: route.key))
    }

    /// Replaces the active tab's page (a draft becoming a note).
    func replaceActive(with route: Route, title: String) {
        guard let id = shell.activeTabID, let index = shell.tabs.firstIndex(where: { $0.id == id }) else {
            open(route, title: title); return
        }
        shell.tabs[index].route = route.key
        shell.tabs[index].title = title
        shell.tabs[index].dot = dot(of: route)
    }

    public func open(course: Course) {
        open(.course(course.id), title: course.name)
    }

    public func open(note: NoteSummary) {
        open(.note(note.id), title: note.title)
    }

    /// Line to reveal and mark when a note opens (a task's source, an outline heading).
    public var reveal: (note: NoteID, line: Int)?

    /// Opens the note a task lives in at the task's line (M7-09).
    public func open(task: TaskItem) {
        let id = task.source.noteID
        reveal = (id, task.source.line)
        let title = courses.notes(of: task.source.courseID ?? "").first { $0.id == id }?.title
        open(.note(id), title: title)
    }

    /// A class opens its note; without one an empty draft that becomes the note on first write.
    public func open(session: SessionOccurrence) {
        let course = session.session.courseID
        if let note = courses.note(for: session) {
            open(note: note)
        } else {
            open(.draft(course: course, date: session.date, title: courses.title(of: session)),
                 title: courses.title(of: session))
        }
    }

    /// Course tabs opened before the catalog loaded get their name and colour.
    func refreshTabTitles() {
        for index in shell.tabs.indices {
            guard let route = shell.tabs[index].route.flatMap(Route.init(key:)) else { continue }
            if case .course(let id) = route, let course = courses.course(id: id) {
                shell.tabs[index].title = course.name
                shell.tabs[index].dot = course.style.dot
            }
        }
    }

    func railSelect(_ id: String) {
        switch id {
        case "home": open(.courses)
        case "inbox": open(.inbox)
        case "today": open(.today)
        case "upcoming": open(.upcoming)
        default:
            if let course = courses.course(id: id) { open(course: course) }
        }
    }

    func dot(of route: Route) -> String {
        switch route {
        case .course(let id), .draft(let id, _, _): courses.course(id: id)?.style.dot ?? Self.grey
        case .note(let id):
            courses.course(id: courses.courseID(ofNote: id) ?? "")?.style.dot ?? Self.grey
        default: Self.grey
        }
    }

    static func title(of route: Route) -> String {
        switch route {
        case .courses: "Courses"
        case .course(let id): id
        case .note(let id): String(id.split(separator: "/").last ?? Substring(id))
        case .draft(_, _, let title): title
        case .inbox: "Inbox"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .graph: "Graph"
        case .search(let q): q.isEmpty ? "Search" : "Search: \(q)"
        case .grades: "Grades"
        case .archive: "Past semesters"
        case .settings: "Settings"
        }
    }

    var rail: RailContent {
        let route = self.route
        var active = route.railID
        if case .note(let id) = route, let course = courses.courseID(ofNote: id) { active = course }
        return RailContent(active: active, inboxHasItems: inboxCount > 0,
                           courses: courses.cards.map { ($0.course.id, $0.course.name, $0.course.style) },
                           initials: "ME")
    }

    /// Inbox size for the rail dot, refreshed by `refreshInbox()`.
    public private(set) var inboxCount = 0

    public func refreshInbox() async {
        inboxCount = (try? await env.inbox.items().count) ?? 0
    }

    // MARK: Messages

    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        public var icon: String
        public var text: String
        public var isError: Bool
    }

    public func show(_ text: String, icon: String = "check_circle", error: Bool = false) {
        toast = Toast(icon: icon, text: text, isError: error)
        let id = toast?.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if self.toast?.id == id { self.toast = nil }
        }
    }

    /// Runs a write; failures become an error toast instead of disappearing.
    func perform(_ what: String, _ body: @escaping () async throws -> Void) {
        Task { @MainActor in
            do { try await body() } catch {
                self.show("\(what) failed: \(Self.describe(error))", icon: "error", error: true)
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? MarginError { return "\(e)" }
        return error.localizedDescription
    }
}
