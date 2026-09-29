/// Graded items of a course and the standing they add up to (M11-01, M10-20). The calculation is
/// `GradeCalculator`; the file is `_grades.md` (spec 05 §7, format in `GradeStore`).
///
/// Implementations: `FixtureGradeService` (in memory) and `VaultGradeService` (reads and writes
/// `_grades.md`). Rules both obey, checked by `Tests/Conformance/GradeServiceConformanceTests.swift`:
///
/// - **Reads:** `grades(course:)` lists the items in file order; a course without `_grades.md` has
///   none. An unknown course is `.notFound`. `average(course:)` is the standing so far
///   (`GradeCalculator.course`, US scale): `nil` while nothing is graded.
/// - **Write context (contract rule 0):** `add` takes `actor`, `baseVersion`, `dryRun` and
///   `idempotencyKey` and returns a `ChangeSet` with one entry for `_grades.md` (`.created` when the
///   file did not exist, else `.modified`). `baseVersion` is `gradesVersion(course:)`; a stale one
///   throws `.conflict`. A dry run changes nothing. A repeated `(actor, idempotencyKey)` returns the
///   first result and writes nothing.
/// - **Validation:** an empty item name, a `max` that is not above 0, a `score` that is negative or not
///   finite, a score without a max, or a weight outside 0...100 is `.invalid`; an item whose name
///   already exists in the course is `.conflict`. The `id` of the `Grade` passed in is ignored: the
///   service derives it from the item name.
/// - **Archived semesters are read-only:** `add` throws `.readOnly`.
public protocol GradeService: Sendable {
    /// The graded items of a course, in file order.
    func grades(course: CourseID) async throws -> [Grade]

    /// The standing of a course so far, or `nil` when nothing is graded yet.
    func average(course: CourseID) async throws -> GradeSummary?

    /// The version of a course's grades for `baseVersion` (hash of `_grades.md`, or of the empty text
    /// when there is no file yet). Throws `.notFound` for an unknown course.
    func gradesVersion(course: CourseID) async throws -> String

    /// Appends an item (`grade.courseID` names the course).
    func add(_ grade: Grade, actor: Actor, baseVersion: String?, dryRun: Bool,
             idempotencyKey: String?) async throws -> ChangeSet
}
