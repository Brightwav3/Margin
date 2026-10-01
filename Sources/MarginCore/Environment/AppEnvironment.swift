import Foundation

/// All services the app runs on. The UI receives one of these and depends on nothing else from the
/// backend: previews and the gallery get `AppEnvironment.fixture(clock:)`, the app gets
/// `AppEnvironment.vault(at:clock:)`. Both satisfy the same protocols and the same conformance
/// tests (contract rules 2 and 3), so a screen built on one runs on the other.
///
/// Add a service by adding a `let` here and a fixture and a vault implementation for it.
public struct AppEnvironment: Sendable {
    public let clock: any Clock
    public let courses: any CourseCatalog
    public let notes: any NoteRepository
    public let tasks: any TaskService
    public let capture: any CaptureService
    public let inbox: any InboxService
    public let properties: any PropertyService
    public let analysis: any NoteAnalysis
    public let graph: any GraphService
    public let courseWriter: any CourseCatalogWriter
    public let settings: any SettingsStore
    public let semesters: any SemesterStore
    public let indexStatus: any IndexStatus
    public let grades: any GradeService
    public let history: any HistoryService
    public let reminders: any ReminderService
    public let syllabus: any SyllabusService
    public let export: any ExportService
    public let search: any SearchService
    public let changes: any ChangeSetStore

    private let onShutdown: @Sendable () async -> Void

    public init(clock: any Clock, courses: any CourseCatalog, notes: any NoteRepository, tasks: any TaskService,
                capture: any CaptureService, inbox: any InboxService,
                properties: any PropertyService, analysis: any NoteAnalysis, graph: any GraphService,
                courseWriter: any CourseCatalogWriter, settings: any SettingsStore, semesters: any SemesterStore,
                indexStatus: any IndexStatus, grades: any GradeService,
                history: any HistoryService, reminders: any ReminderService,
                syllabus: any SyllabusService, export: any ExportService, search: any SearchService,
                changes: any ChangeSetStore,
                shutdown: @escaping @Sendable () async -> Void = {}) {
        self.clock = clock; self.courses = courses; self.notes = notes; self.tasks = tasks
        self.properties = properties; self.analysis = analysis; self.capture = capture; self.inbox = inbox
        self.graph = graph; self.courseWriter = courseWriter; self.grades = grades; self.history = history
        self.settings = settings; self.semesters = semesters; self.indexStatus = indexStatus
        self.reminders = reminders; self.syllabus = syllabus; self.export = export; self.search = search
        self.changes = changes
        self.onShutdown = shutdown
    }

    /// Stops background work (file watching) and ends every update stream. Call when the window
    /// or the app goes away; the services keep answering reads afterwards but report no changes.
    public func shutdown() async { await onShutdown() }

    /// In-memory services over `Fixtures.week5`. Writes change memory only. The default clock is
    /// the fixture clock (Monday 28 Sep 2026, 13:24).
    public static func fixture(clock: any Clock = FixedClock(),
                               reminderCenter: any ReminderCenter = InMemoryReminderCenter()) -> AppEnvironment {
        let store = FixtureStore(world: Fixtures.week5, clock: clock)
        let settings = FixtureSettingsStore()
        return AppEnvironment(
            clock: clock,
            courses: FixtureCourseCatalog(store: store),
            notes: FixtureNoteRepository(store: store),
            tasks: FixtureTaskService(store: store),
            capture: FixtureCaptureService(store: store),
            inbox: FixtureInboxService(store: store),
            properties: FixturePropertyService(store: store),
            analysis: FixtureNoteAnalysis(store: store),
            graph: FixtureGraphService(world: Fixtures.week5),
            courseWriter: FixtureCourseCatalogWriter(store: store),
            settings: settings, semesters: FixtureSemesterStore(store: store),
            indexStatus: FixtureIndexStatus(store: store),
            grades: FixtureGradeService(store: store),
            history: FixtureHistoryService(store: store, clock: clock),
            reminders: CatalogReminderService(courses: FixtureCourseCatalog(store: store), center: reminderCenter, clock: clock),
            syllabus: FixtureSyllabusService(store: store),
            export: FixtureExportService(store: store),
            search: FixtureSearchService(store: store),
            changes: FixtureChangeSetStore(store: store),
            shutdown: { store.catalogUpdates.finishAll(); store.noteChanges.finishAll(); store.taskChanges.finishAll()
                settings.finish() })
    }
}
