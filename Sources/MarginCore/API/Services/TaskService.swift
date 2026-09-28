/// Tasks found in notes (`- [ ] text @date ^id`) and exams, read side. M7 adds `toggle`,
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
/// - **Errors:** `tasks(course:)` throws `MarginError.notFound` for an unknown course.
public protocol TaskService: Sendable {
    /// Open tasks due today or overdue, plus exams dated today.
    func today() async throws -> [TaskItem]

    /// Open tasks and exams due after today.
    func upcoming() async throws -> [TaskItem]

    /// All tasks of a course, done and open, with or without due date.
    func tasks(course: CourseID) async throws -> [TaskItem]
}
