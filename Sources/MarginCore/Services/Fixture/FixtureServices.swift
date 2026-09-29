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

    public func toggle(id: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await store.toggleTask(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                   idempotencyKey: idempotencyKey)
    }

    public var updates: AsyncStream<TaskUpdate> { store.taskChanges.subscribe() }
}

/// `PropertyService` over `Fixtures.week5`, in memory. Notes carry the frontmatter the sample vault
/// writes (`id`, `date`, `class`, `type`), so properties behave as in the vault.
public struct FixturePropertyService: PropertyService {
    let store: FixtureStore

    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.store = FixtureStore(world: world, clock: clock)
    }

    init(store: FixtureStore) { self.store = store }

    public func types() async throws -> [String: PropertyType] { await store.propertyTypes() }

    public func set(key: String, value: FrontmatterValue, on note: NoteID, actor: Actor, baseVersion: String?,
                    dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await store.setProperty(key: key, value: value, on: note, actor: actor, baseVersion: baseVersion,
                                    dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func remove(key: String, on note: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await store.removeProperty(key: key, on: note, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                       idempotencyKey: idempotencyKey)
    }
}

/// `NoteAnalysis` over `Fixtures.week5`, in memory. Answers from a `NoteIndex` built over the fixture
/// notes, so it follows note writes like the vault does.
public struct FixtureNoteAnalysis: NoteAnalysis {
    let store: FixtureStore
    private let engine: NoteAnalysisEngine

    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.init(store: FixtureStore(world: world, clock: clock))
    }

    init(store: FixtureStore) {
        self.store = store
        self.engine = NoteAnalysisEngine(index: { await store.noteIndex() }, isNote: { _ in true })
    }

    public func outline(id: NoteID) async throws -> [OutlineItem] { try await engine.outline(id: id) }
    public func backlinks(id: NoteID) async throws -> [NoteBacklink] { try await engine.backlinks(id: id) }
    public func outgoing(id: NoteID) async throws -> [OutgoingLink] { try await engine.outgoing(id: id) }
    public func stats(id: NoteID, text: String?) async throws -> NoteStats { try await engine.stats(id: id, text: text) }
    public func properties(id: NoteID) async throws -> [NoteProperty] { try await engine.properties(id: id) }
}

/// `CourseCatalogWriter` over `Fixtures.week5`, in memory. Writes change memory only and show up in
/// `FixtureCourseCatalog` when both share a store (`AppEnvironment.fixture`).
public struct FixtureCourseCatalogWriter: CourseCatalogWriter {
    let store: FixtureStore

    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.store = FixtureStore(world: world, clock: clock)
    }

    init(store: FixtureStore) { self.store = store }

    public func courseVersion(id: CourseID) async throws -> String { try await store.courseVersion(id: id) }

    public func create(_ course: NewCourse, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await store.createCourse(course, actor: actor, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func rename(id: CourseID, to name: String, renameFolder: Bool, actor: Actor, baseVersion: String?,
                       dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await store.renameCourse(id: id, to: name, renameFolder: renameFolder, actor: actor,
                                     baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func setStyle(id: CourseID, icon: String?, color: String?, actor: Actor, baseVersion: String?,
                         dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await store.setCourseStyle(id: id, icon: icon, color: color, actor: actor, baseVersion: baseVersion,
                                       dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func setArchived(semester: SemesterID, _ archived: Bool, actor: Actor, baseVersion: String?,
                            dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await store.setArchived(semester: semester, archived, actor: actor, dryRun: dryRun,
                                    idempotencyKey: idempotencyKey)
    }

    public func override(session: SessionOverride, actor: Actor, baseVersion: String?, dryRun: Bool,
                         idempotencyKey: String?) async throws -> ChangeSet {
        try await store.setOverride(session, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                    idempotencyKey: idempotencyKey)
    }

    public func clearOverride(sessionID: String, course: CourseID, originalDate: LocalDate, actor: Actor,
                              baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await store.removeOverride(sessionID: sessionID, course: course, originalDate: originalDate, actor: actor,
                                       baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }
}
