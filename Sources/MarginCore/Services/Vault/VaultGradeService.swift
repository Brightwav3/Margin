/// `GradeService` over a vault: `_grades.md` next to each course's `_course.md`.
public struct VaultGradeService: GradeService {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func grades(course: CourseID) async throws -> [Grade] { try await backend.grades(course: course) }
    public func average(course: CourseID) async throws -> GradeSummary? { try await backend.gradeAverage(course: course) }
    public func gradesVersion(course: CourseID) async throws -> String { try await backend.gradesVersion(course: course) }

    public func add(_ grade: Grade, actor: Actor, baseVersion: String?, dryRun: Bool,
                    idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.addGrade(grade, actor: actor, baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }
}
