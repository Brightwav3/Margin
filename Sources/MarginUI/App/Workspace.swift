import AppKit
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
    /// Quick capture over the window (5a).
    public let capture: CaptureModel
    /// Short-lived message at the bottom of the window (1i toasts).
    public var toast: Toast?
    /// Modal dialog over the window (M10c).
    public var dialog: Dialog?

    public enum HelpTopic: String, Sendable { case shortcuts, markdown, whatsNew }

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
        case renameCourse(Course)
        case courseStyle(Course)
        case help(HelpTopic)

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
            case .renameCourse(let c): "rename/\(c.id)"
            case .courseStyle(let c): "style/\(c.id)"
            case .help(let t): "help/\(t.rawValue)"
            }
        }
    }

    @ObservationIgnored private var models: [String: AnyObject] = [:]
    var allModels: [AnyObject] { Array(models.values) }
    var activeEditor = ActiveEditor()
    /// The palette was opened from `+`: its note opens in a new tab.
    public var openInNewTab = false
    @ObservationIgnored var recents: [(id: NoteID, title: String)] = []

    /// Folder of the vault on disk; nil on fixture data.
    public let vaultURL: URL?

    public init(env: AppEnvironment, shell: AppModel? = nil, start: Route = .courses, vaultURL: URL? = nil) {
        self.env = env
        self.vaultURL = vaultURL
        self.courses = CoursesOverviewModel(env: env)
        self.capture = CaptureModel(env: env)
        self.shell = shell ?? AppModel()
        capture.onSaved = { [weak self] _, toInbox in
            guard let self else { return }
            self.show(toInbox ? "Added to Inbox" : "Saved", icon: toInbox ? "inbox" : "check_circle")
            Task { await self.refreshAfterWrite() }
        }
        if self.shell.tabs.isEmpty {
            if start.isNote {
                self.shell.open(ShellTab(title: Self.title(of: start), dot: Self.grey, route: start.key))
            } else {
                self.shell.place = start.key
            }
        }
    }

    static let grey = "#9A9DA6"

    /// What the content area shows: the active note tab, else the current place.
    public var route: Route {
        if let tab = shell.activeTab, let r = tab.route.flatMap(Route.init(key:)) { return r }
        return Route(key: shell.place) ?? .courses
    }

    /// The model of a route, created on first use.
    func model<M: AnyObject>(_ key: String, make: () -> M) -> M {
        if let existing = models[key] as? M { return existing }
        let made = make()
        models[key] = made
        return made
    }

    func forget(_ key: String) { models[key] = nil }

    /// Moves a screen model to another route (a draft that became a note).
    func adopt(_ model: AnyObject, from: Route, to: Route) {
        models[from.key] = nil
        models[to.key] = model
    }

    /// Note routes that already switched the sidebar to the Notes space once.
    @ObservationIgnored var notesPageShown: Set<String> = []

    // MARK: Navigation

    /// Shows `route` in its open tab or a new one.
    /// Notes open in the one tab (a new tab with `newTab` or ⌘ held); every other page is a place
    /// shown without a tab.
    public func open(_ route: Route, title: String? = nil, newTab: Bool? = nil) {
        guard route.isNote else { shell.showPlace(route.key); return }
        let title = title ?? Self.title(of: route)
        noteOpened(route, title: title)
        let wantsNewTab = newTab ?? (NSApp.currentEvent?.modifierFlags.contains(.command) == true
                                     && NSApp.currentEvent?.type == .leftMouseUp)
        shell.show(ShellTab(title: title, dot: dot(of: route), route: route.key), newTab: wantsNewTab)
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

    /// Every route change goes through here; notes are remembered for File › Open recent.
    func noteOpened(_ route: Route, title: String) {
        if case .note(let id) = route { remember(note: id, title: title) }
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

    /// Sets the title (and dot) of the tabs showing `route`.
    func retitle(route: Route, title: String) {
        for index in shell.tabs.indices where shell.tabs[index].route == route.key {
            if shell.tabs[index].title != title { shell.tabs[index].title = title }
            let dot = dot(of: route)
            if shell.tabs[index].dot != dot { shell.tabs[index].dot = dot }
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

    /// Note id of a `[[target]]` (title, file name or alias).
    public func resolve(link target: String) async -> NoteID? {
        let name = target.split(separator: "#").first.map(String.init) ?? target
        let found = (try? await env.search.suggestLinks(prefix: name, course: nil, note: nil, limit: 20)) ?? []
        return found.first { $0.kind != .create && $0.title.caseInsensitiveCompare(name) == .orderedSame }?.noteID
            ?? found.first { $0.kind == .alias }?.noteID
    }

    /// Follows a wikilink; a link to a note that does not exist yet creates it in the same course.
    public func openLink(_ target: String, from course: CourseID?, newTab: Bool? = nil) {
        let name = target.split(separator: "#").first.map(String.init) ?? target
        Task { @MainActor in
            if let id = await resolve(link: name) {
                open(.note(id), title: name, newTab: newTab)
            } else if let course = course ?? courses.cards.first?.id {
                perform("Create note") {
                    let change = try await self.env.notes.create(course: course, title: name, kind: .study,
                                                                 text: "# \(name)\n\n", actor: .user, baseVersion: nil,
                                                                 dryRun: false, idempotencyKey: nil)
                    if let id = change.entries.first?.noteID { self.open(.note(id), title: name) }
                    await self.courses.load()
                }
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

    /// After a write from outside a page (capture, dialogs): refresh what lists it.
    public func refreshAfterWrite() async {
        await refreshInbox()
        await courses.load()
        for (key, model) in models {
            switch model {
            case let m as TasksModel: await m.load()
            case let m as CourseDetailModel: await m.load()
            case let m as InboxModel: await m.load()
            default: _ = key
            }
        }
    }

    // MARK: Commands (⌘K, M10-02)

    /// App commands for the palette; ids are run by `run(command:)`.
    public let commands: CommandRegistry = {
        var r = CommandRegistry()
        let list: [(String, String, [String], String, String?)] = [
            ("capture", "Quick capture", ["new task", "inbox", "add"], "Create", "⌘⇧Space"),
            ("new-note", "New note in this course", ["create", "write"], "Create", "⌘N"),
            ("new-course", "New course", ["add course", "subject"], "Create", nil),
            ("today", "Go to Today", ["tasks", "due"], "Go to", nil),
            ("upcoming", "Go to Upcoming", ["tasks", "week", "exams"], "Go to", nil),
            ("inbox", "Go to Inbox", ["triage", "captured"], "Go to", nil),
            ("courses", "Go to Courses", ["home", "grid"], "Go to", nil),
            ("timetable", "Show timetable", ["week", "schedule", "sessions"], "Go to", nil),
            ("graph", "Open graph map", ["links", "connections"], "Go to", nil),
            ("grades", "Open grades", ["average", "gpa", "marks"], "Go to", nil),
            ("archive", "Past semesters", ["archive", "old"], "Go to", nil),
            ("settings", "Open settings", ["preferences", "options"], "Go to", "⌘,"),
            ("grade", "Enter a grade", ["mark", "score"], "Course", nil),
            ("syllabus", "Import syllabus", ["schedule", "exams", "pdf"], "Course", nil),
            ("toggle-sidebar", "Toggle sidebar", ["panel"], "View", "⌥⌘S"),
            ("toggle-inspector", "Toggle inspector", ["panel", "outline"], "View", "⌥⌘I"),
        ]
        for c in list { try? r.register(Command(id: c.0, title: c.1, keywords: c.2, group: c.3, shortcut: c.4)) }
        return r
    }()

    /// Course of the active page (course detail, a note of a course, a draft).
    public var currentCourse: CourseID? {
        switch route {
        case .course(let id), .draft(let id, _, _): id
        case .note(let id): courses.courseID(ofNote: id)
        default: nil
        }
    }

    public func run(command id: String) {
        switch id {
        case "capture": capture.open()
        case "new-note":
            if let c = currentCourse ?? courses.cards.first?.id { newNote(in: courseModel(c)) }
        case "new-course": dialog = .newCourse
        case "today": open(.today)
        case "upcoming": open(.upcoming)
        case "inbox": open(.inbox)
        case "courses": courses.mode = .grid; open(.courses)
        case "timetable": courses.mode = .timetable; open(.courses)
        case "graph": open(.graph)
        case "grades": open(.grades)
        case "archive": open(.archive)
        case "settings": open(.settings)
        case "grade": if let c = currentCourse ?? courses.cards.first?.id { dialog = .grade(c) }
        case "syllabus": if let c = currentCourse ?? courses.cards.first?.id { dialog = .syllabus(c) }
        case "toggle-sidebar": shell.toggleSidebar()
        case "toggle-inspector": shell.toggleInspector()
        default: break
        }
    }

    /// Closes the tabs of a route (a deleted note).
    func closeTabs(of route: Route) {
        for tab in shell.tabs where tab.route == route.key { shell.close(tab.id) }
        forget(route.key)
        if shell.tabs.isEmpty, route.isNote, let course = courses.courseID(ofNote: route.key.replacingOccurrences(of: "note/", with: "")) {
            shell.showPlace(Route.course(course).key)
        }
    }

    /// Reloads an open editor after its note changed from a dialog (restore).
    func reloadEditor(_ id: NoteID) async {
        if let m = models[Route.note(id).key] as? NoteEditorModel { await m.load() }
        await refreshAfterWrite()
    }

    // MARK: First run and index

    /// Onboarding shows while the vault has no semester, until the user continues past step 3.
    public var onboardingDone = false
    public var needsOnboarding: Bool {
        !onboardingDone && courses.isLoaded && courses.semesters.isEmpty
            || (!onboardingDone && startedOnboarding)
    }
    @ObservationIgnored private var startedOnboarding = false

    func finishOnboarding() {
        onboardingDone = true
        Task { await courses.load() }
    }

    /// Latest index progress; complete (or nil) hides the loading screen.
    public private(set) var indexProgress: IndexProgress?

    public func watchIndex() async {
        for await p in env.indexStatus.progress {
            indexProgress = p
            if p.isComplete { await refreshAfterWrite() }
        }
    }

    /// Editor defaults from Settings (readable line length, first view, properties panel).
    public internal(set) var editorDefaults = EditorDefaults()

    public struct EditorDefaults: Sendable {
        public var readableLineLength = true
        public var mode: EditorMode = .live
        public var showProperties = true
    }

    public func applySettings() {
        Task { @MainActor in
            let view = await env.settings.get(Settings.defaultView)
            editorDefaults = EditorDefaults(
                readableLineLength: await env.settings.get(Settings.readableLineLength),
                mode: view == .reading ? .reading : view == .source ? .source : .live,
                showProperties: await env.settings.get(Settings.showProperties))
            for case let m as NoteEditorModel in models.values { m.readableLineLength = editorDefaults.readableLineLength }
        }
    }

    func gradesModel() -> GradesModel { model("grades") { GradesModel(env: env) } }
    func settingsModel() -> SettingsModel { model("settings") { SettingsModel(env: env) } }
    func searchModel(_ query: String) -> SearchModel { model(Route.search(query).key) { SearchModel(env: env, query: query) } }

    func graphModel() -> GraphModel { model("graph") { GraphModel(env: env) } }

    /// Local graph around a note (note menu „Open linked view“, M9-08).
    public func openLocalGraph(_ note: NoteID) {
        graphModel().focus = note
        open(.graph)
    }

    func inboxModel() -> InboxModel { model("inbox") { InboxModel(env: env) } }

    // MARK: Reminders (1i)

    /// A class starting soon: shown as a toast with its note (the system notification is scheduled
    /// by `ReminderService` in the app).
    public var soonClass: SessionOccurrence?
    @ObservationIgnored private var announced: Set<String> = []

    /// Checks every 30 s for a class starting within `Settings.reminderMinutes`.
    public func watchUpcomingClasses() async {
        while !Task.isCancelled {
            let minutes = await env.settings.get(Settings.reminderMinutes)
            let now = env.clock.localNow
            if let semester = courses.semester, let week = env.clock.weekOfSemester(semester),
               let sessions = try? await env.courses.sessions(week: week) {
                let soon = sessions.first { s in
                    guard !s.isCancelled, s.date == now.date else { return false }
                    let delta = s.session.start.minutesSinceMidnight - now.time.minutesSinceMidnight
                    return delta > 0 && delta <= minutes
                }
                if let soon, !announced.contains(soon.id) {
                    announced.insert(soon.id)
                    soonClass = soon
                }
            }
            try? await Task.sleep(for: .seconds(30))
        }
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
