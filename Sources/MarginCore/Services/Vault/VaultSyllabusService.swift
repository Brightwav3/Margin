/// `SyllabusService` over a vault: edits `_course.md` losslessly.
public struct VaultSyllabusService: SyllabusService {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func draft(course: CourseID) async throws -> SyllabusDraft { try await backend.syllabusDraft(course: course) }

    public func apply(_ draft: SyllabusDraft, to course: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
                      idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.applySyllabus(draft, to: course, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                        idempotencyKey: idempotencyKey)
    }
}
