import Foundation

/// `CourseCatalog` over a vault: courses come from `_course.md` files (spec 05 §5), semesters from
/// `.margin/semesters.json`. Changes made to those files by other programs arrive on `updates`.
public struct VaultCourseCatalog: CourseCatalog {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func semesters() async throws -> [Semester] { await backend.semesters() }
    public func courses(query: String?) async throws -> [Course] { await backend.courses(query: query) }
    public func course(id: CourseID) async throws -> Course { try await backend.course(id: id) }
    public func sessions(week: Int) async throws -> [SessionOccurrence] { try await backend.sessions(week: week) }
    public var updates: AsyncStream<CatalogUpdate> { backend.catalogUpdates.subscribe() }
}

/// `NoteRepository` over a vault: reads through the note index, writes atomically through
/// `VaultStore`. Notes moved to the trash by `delete` land in the system trash (macOS) or in
/// `.margin/trash/`.
///
/// A note's id is the `id:` in its frontmatter, else its path without `.md`; a note without `id:`
/// therefore gets a new id when it is moved (stable ids arrive with MA0, AG-02).
public struct VaultNoteRepository: NoteRepository {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func notes(course: CourseID?) async throws -> [NoteSummary] { try await backend.notes(course: course) }
    public func open(id: NoteID) async throws -> Note { try await backend.open(id: id) }

    public func save(id: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                     idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.save(id: id, text: text, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                               idempotencyKey: idempotencyKey)
    }

    public func create(course: CourseID, title: String, kind: NoteKind, text: String, actor: Actor,
                       baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.create(course: course, title: title, kind: kind, text: text, actor: actor,
                                 dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func move(id: NoteID, toCourse: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
                     idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.move(id: id, toCourse: toCourse, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                               idempotencyKey: idempotencyKey)
    }

    public func delete(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.delete(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                 idempotencyKey: idempotencyKey)
    }

    public var externalChanges: AsyncStream<[NoteChange]> { backend.noteChanges.subscribe() }
}

/// `TaskService` over a vault: tasks are those the note index found (`- [ ] text @date ^id`).
public struct VaultTaskService: TaskService {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func today() async throws -> [TaskItem] { await backend.today() }
    public func upcoming() async throws -> [TaskItem] { await backend.upcoming() }
    public func tasks(course: CourseID) async throws -> [TaskItem] { try await backend.tasks(course: course) }
}

/// `ChangeSetStore` over a vault: every write of the `Vault…` services is recorded in
/// `.margin/changesets/` (write-ahead, so an interrupted write is rolled back on the next open)
/// and can be undone here, also after the app was restarted.
public struct VaultChangeSetStore: ChangeSetStore {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func changes(limit: Int?) async throws -> [ChangeSet] { await backend.changes(limit: limit) }
    public func change(id: String) async throws -> ChangeSet { try await backend.change(id: id) }
    public func undo(id: String, actor: Actor, mode: UndoMode, dryRun: Bool) async throws -> ChangeSet {
        try await backend.undo(id: id, actor: actor, mode: mode, dryRun: dryRun)
    }
}
