/// Tasks found in notes (`- [ ] text @date ^id`) and exams. Reading, `updates` and `toggle`; M7 adds
/// `setDue` and the rest of the write side.
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
/// - **Updates:** `updates` reports a change to any task within 1 s of it happening: an edit made
///   by another program, or a write through `NoteRepository`. An edit that leaves every task as it
///   was (prose only) reports nothing. `today()`, `upcoming()` and `tasks(course:)` already show the
///   change when the update arrives.
/// - **Toggle:** `toggle` flips `- [ ]` and `- [x]` on the task's line in its note, changing that one
///   character and nothing else, atomically. It takes the write context of contract rule 0 (`baseVersion`
///   is the note's `Note.version`); the `ChangeSet` has one `.modified` entry for the note. The task is
///   found again in the current text (`^id`, then text), so a stale line number cannot flip the wrong
///   line, and `updates` reports the change.
/// - **Errors:** `tasks(course:)` throws `MarginError.notFound` for an unknown course. `toggle` throws
///   `.notFound` for an unknown task id or one that is no longer in its note, `.invalid` for an exam,
///   `.conflict` for a stale `baseVersion`.
public protocol TaskService: Sendable {
    /// Open tasks due today or overdue, plus exams dated today.
    func today() async throws -> [TaskItem]

    /// Open tasks and exams due after today.
    func upcoming() async throws -> [TaskItem]

    /// All tasks of a course, done and open, with or without due date.
    func tasks(course: CourseID) async throws -> [TaskItem]

    /// A new stream on every access. Each element says which notes and courses have changed tasks.
    /// The stream stays open until the consumer stops iterating or the environment shuts down.
    var updates: AsyncStream<TaskUpdate> { get }

    /// Flips a task between open and done. `id` is `TaskItem.id`.
    func toggle(id: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet
}
