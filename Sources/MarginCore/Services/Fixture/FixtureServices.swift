/// `CourseCatalog` over `Fixtures.week5`, in memory. Same observable behaviour as
/// `VaultCourseCatalog` (contract rule 2 and 3).
public struct FixtureCourseCatalog: CourseCatalog {
    let store: FixtureStore

    /// A catalog with its own private state.
    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.store = FixtureStore(world: world, clock: clock)
    }

    init(store: FixtureStore) { self.store = store }

    public func semesters() async throws -> [Semester] { await store.semesters() }
    public func courses(query: String?) async throws -> [Course] { await store.courses(query: query) }
    public func course(id: CourseID) async throws -> Course { try await store.course(id: id) }
    public func sessions(week: Int) async throws -> [SessionOccurrence] { try await store.sessions(week: week) }
    public var updates: AsyncStream<CatalogUpdate> { store.catalogUpdates.subscribe() }
}

/// `NoteRepository` over `Fixtures.week5`, in memory. Writes change the in-memory state only.
public struct FixtureNoteRepository: NoteRepository {
    let store: FixtureStore

    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.store = FixtureStore(world: world, clock: clock)
    }

    init(store: FixtureStore) { self.store = store }

    public func notes(course: CourseID?) async throws -> [NoteSummary] { try await store.notes(course: course) }
    public func open(id: NoteID) async throws -> Note { try await store.open(id: id) }

    public func save(id: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                     idempotencyKey: String?) async throws -> ChangeSet {
        try await store.save(id: id, text: text, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                             idempotencyKey: idempotencyKey)
    }

    public func create(course: CourseID, title: String, kind: NoteKind, text: String, actor: Actor,
                       baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await store.create(course: course, title: title, kind: kind, text: text, actor: actor,
                               dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func move(id: NoteID, toCourse: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
                     idempotencyKey: String?) async throws -> ChangeSet {
        try await store.move(id: id, toCourse: toCourse, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                             idempotencyKey: idempotencyKey)
    }

    public func delete(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await store.delete(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                               idempotencyKey: idempotencyKey)
    }

    public var externalChanges: AsyncStream<[NoteChange]> { store.noteChanges.subscribe() }
}

/// `TaskService` over `Fixtures.week5`, in memory. Tasks are read from the note bodies, so they
/// follow note writes exactly as in the vault.
public struct FixtureTaskService: TaskService {
    let store: FixtureStore

    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.store = FixtureStore(world: world, clock: clock)
    }

    init(store: FixtureStore) { self.store = store }

    public func today() async throws -> [TaskItem] { await store.today() }
    public func upcoming() async throws -> [TaskItem] { await store.upcoming() }
    public func tasks(course: CourseID) async throws -> [TaskItem] { try await store.tasks(course: course) }
}
