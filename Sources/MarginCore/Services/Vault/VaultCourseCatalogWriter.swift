import Foundation

/// `CourseCatalogWriter` over a vault: edits `_course.md` files losslessly and moves folders through
/// `VaultStore` (atomic, `expectedVersion`), then brings the index and the course model up to date.
public struct VaultCourseCatalogWriter: CourseCatalogWriter {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func courseVersion(id: CourseID) async throws -> String { try await backend.courseVersion(id: id) }

    public func create(_ course: NewCourse, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.createCourse(course, actor: actor, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func rename(id: CourseID, to name: String, renameFolder: Bool, actor: Actor, baseVersion: String?,
                       dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.renameCourse(id: id, to: name, renameFolder: renameFolder, actor: actor,
                                       baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func setStyle(id: CourseID, icon: String?, color: String?, actor: Actor, baseVersion: String?,
                         dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.setCourseStyle(id: id, icon: icon, color: color, actor: actor, baseVersion: baseVersion,
                                         dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func setArchived(semester: SemesterID, _ archived: Bool, actor: Actor, baseVersion: String?,
                            dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.setArchived(semester: semester, archived, actor: actor, dryRun: dryRun,
                                      idempotencyKey: idempotencyKey)
    }

    public func override(session: SessionOverride, actor: Actor, baseVersion: String?, dryRun: Bool,
                         idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.setOverride(session, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                      idempotencyKey: idempotencyKey)
    }

    public func clearOverride(sessionID: String, course: CourseID, originalDate: LocalDate, actor: Actor,
                              baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.clearOverride(sessionID: sessionID, course: course, originalDate: originalDate, actor: actor,
                                        baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }
}
