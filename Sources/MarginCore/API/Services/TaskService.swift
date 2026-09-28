/// Tasks found in notes (`- [ ] text @date ^id`) and exams. Reading, and `toggle`; M7 adds `setDue`
/// and the rest of the write side.
///
/// Implementations: `FixtureTaskService` and `VaultTaskService`. Rules both obey (checked by
/// `Tests/Conformance/TaskServiceConformanceTests.swift`):
///
/// - **Today:** `today()` returns open tasks due today or earlier (overdue first) and exams dated
///   today. Done tasks and tasks without a due date are not included.
/// - **Upcoming:** `upcoming()` returns open tasks and exams due after today.
/// - **Day boundary:** "today" is the `Clock`'s local day; `label` on every item is computed against
///   it at call time, so a call made after local midnight sees the new day.
/// - **Ordering:** `today()` and `upcoming()` sort by due date, course id, then item id.
///   `tasks(course:)` sorts by note id, then line.
/// - **Exams** are `TaskItem`s of kind `.exam` derived from the course's exams (id `exam-<exam.id>`,
///   source note `<course>/_course`); they never appear in `tasks(course:)`.
/// - **Toggle:** `toggle` flips `- [ ]` and `- [x]` on the task's line in its note, changing that one
///   character and nothing else, atomically. It takes the write context of contract rule 0 (`baseVersion`
///   is the note's `Note.version`); the `ChangeSet` has one `.modified` entry for the note. The task is
///   found again in the current text, so a stale line number cannot flip the wrong line.
/// - **Errors:** `tasks(course:)` throws `MarginError.notFound` for an unknown course. `toggle` throws
///   `.notFound` for an unknown task id, `.invalid` for an exam, `.conflict` for a stale `baseVersion` or
///   a task that changed since it was indexed.
public protocol TaskService: Sendable {
    /// Open tasks due today or overdue, plus exams dated today.
    func today() async throws -> [TaskItem]

    /// Open tasks and exams due after today.
    func upcoming() async throws -> [TaskItem]

    /// All tasks of a course, done and open, with or without due date.
    func tasks(course: CourseID) async throws -> [TaskItem]

    /// Flips a task between open and done. `id` is `TaskItem.id`.
    func toggle(id: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet
}
