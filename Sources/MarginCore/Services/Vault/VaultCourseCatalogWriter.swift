import Foundation

/// `CourseCatalogWriter` over a vault: edits `_course.md` files losslessly and moves folders through
/// `VaultStore` (atomic, `expectedVersion`), then brings the index and the course model up to date.
public struct VaultCourseCatalogWriter: CourseCatalogWriter {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func courseVersion(id: CourseID) async throws -> String { 
        throw MarginError.invalid("Course versions are not implemented yet (TODO(M10-12.B))")
    }

    public func create(_ course: NewCourse, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        throw MarginError.invalid("Creating courses is not implemented yet (TODO(M10-16.B))")
    }

    public func rename(id: CourseID, to name: String, renameFolder: Bool, actor: Actor, baseVersion: String?,
                       dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        throw MarginError.invalid("Renaming courses is not implemented yet (TODO(M10-12.B))")
    }

    public func setStyle(id: CourseID, icon: String?, color: String?, actor: Actor, baseVersion: String?,
                         dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        throw MarginError.invalid("Course styles are not implemented yet (TODO(M10-12.B))")
    }

    public func setArchived(semester: SemesterID, _ archived: Bool, actor: Actor, baseVersion: String?,
                            dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        throw MarginError.invalid("Archiving semesters is not implemented yet (TODO(M10-13.B))")
    }

    public func override(session: SessionOverride, actor: Actor, baseVersion: String?, dryRun: Bool,
                         idempotencyKey: String?) async throws -> ChangeSet {
        throw MarginError.invalid("Session overrides are not implemented yet (TODO(M10-14.B))")
    }

    public func clearOverride(sessionID: String, course: CourseID, originalDate: LocalDate, actor: Actor,
                              baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        throw MarginError.invalid("Session overrides are not implemented yet (TODO(M10-14.B))")
    }
}
