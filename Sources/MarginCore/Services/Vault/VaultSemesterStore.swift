import Foundation

/// `SemesterStore` over a vault: `.margin/semesters.json` and the semester folders. A created semester
/// also gets its (empty) folder, made by `SemesterFactory`.
public struct VaultSemesterStore: SemesterStore {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func semesters() async throws -> [Semester] { await backend.semesters() }
    public func current() async throws -> Semester? { await backend.currentSemester() }
    public func version() async throws -> String { try await backend.semesterVersion() }

    public func create(_ semester: NewSemester, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.createSemester(semester, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                         idempotencyKey: idempotencyKey)
    }

    public func update(id: SemesterID, _ update: SemesterUpdate, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.updateSemester(id: id, update, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                         idempotencyKey: idempotencyKey)
    }

    public func delete(id: SemesterID, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.deleteSemester(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                         idempotencyKey: idempotencyKey)
    }
}
