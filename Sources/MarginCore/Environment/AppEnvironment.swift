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

    private let onShutdown: @Sendable () async -> Void

    public init(clock: any Clock, courses: any CourseCatalog, notes: any NoteRepository, tasks: any TaskService,
                capture: any CaptureService, inbox: any InboxService,
                shutdown: @escaping @Sendable () async -> Void = {}) {
        self.clock = clock; self.courses = courses; self.notes = notes; self.tasks = tasks; self.capture = capture; self.inbox = inbox
        self.onShutdown = shutdown
    }

    /// Stops background work (file watching) and ends every update stream. Call when the window
    /// or the app goes away; the services keep answering reads afterwards but report no changes.
    public func shutdown() async { await onShutdown() }

    /// In-memory services over `Fixtures.week5`. Writes change memory only. The default clock is
    /// the fixture clock (Monday 28 Sep 2026, 13:24).
    public static func fixture(clock: any Clock = FixedClock()) -> AppEnvironment {
        let store = FixtureStore(world: Fixtures.week5, clock: clock)
        return AppEnvironment(
            clock: clock,
            courses: FixtureCourseCatalog(store: store),
            notes: FixtureNoteRepository(store: store),
            tasks: FixtureTaskService(store: store),
            capture: FixtureCaptureService(store: store),
            inbox: FixtureInboxService(store: store),
            shutdown: { store.catalogUpdates.finishAll(); store.noteChanges.finishAll(); store.taskChanges.finishAll() })
    }
}
