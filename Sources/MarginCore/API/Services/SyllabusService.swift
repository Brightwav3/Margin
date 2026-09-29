/// Writing a syllabus into a course (M10-19). The read side is `CourseCatalog`; after `apply`,
/// `course(id:)`, `sessions(week:)`, the exams in Today/Upcoming and `updates` show the change.
///
/// Rules both implementations obey, checked by `Tests/Conformance/SyllabusServiceConformanceTests.swift`:
///
/// - **Write context (contract rule 0):** `apply` takes `actor`, `baseVersion` (the value of
///   `CourseCatalogWriter.courseVersion(id:)`), `dryRun` and `idempotencyKey` and returns a
///   `ChangeSet` with one `.modified` entry for `_course.md`; a draft that changes nothing gives an
///   empty one. A stale `baseVersion` throws `.conflict`; a dry run changes nothing; a repeated
///   `(actor, idempotencyKey)` returns the first result.
/// - **Sections:** only the sections of the draft that are not `nil` and differ from the course are
///   written, in the lossless way of `CourseCatalogWriter`: other keys, their order, comments, the
///   body and the overrides stay byte for byte. An untouched section is not rewritten.
/// - **Validation (`.invalid`, nothing written):** a session needs a length above 0 and at most 12
///   hours and two sessions cannot share a day and time; an exam needs a title, no two share title and
///   date, and a weight of 0...100; a grading part needs a label (unique, ignoring case) and a weight of
///   0...100, and the weights together are at most 100. Weights that do not add up to 100 are only a
///   `SyllabusDraft.warnings` entry.
/// - **Errors:** unknown course is `.notFound`; a course of an archived semester is `.readOnly`.
public protocol SyllabusService: Sendable {
    /// The draft that says what the course says now, to start editing from.
    func draft(course: CourseID) async throws -> SyllabusDraft

    /// Writes the draft into the course.
    func apply(_ draft: SyllabusDraft, to course: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
               idempotencyKey: String?) async throws -> ChangeSet
}
