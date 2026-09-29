/// A change to the set of tasks, delivered by `TaskService.updates`.
///
/// It says *where* something changed, not what: the consumer asks `today()`, `upcoming()` or
/// `tasks(course:)` again. That keeps one code path for the first load and for every refresh.
public struct TaskUpdate: Codable, Sendable, Hashable {
    /// Notes whose tasks were added, removed, edited, ticked, moved to another line or course, or
    /// whose note was deleted. Sorted.
    public var noteIDs: [NoteID]
    /// Courses affected: those of the changed notes (before and after a move) and courses whose
    /// exams changed. Sorted.
    public var courseIDs: [CourseID]

    public init(noteIDs: [NoteID], courseIDs: [CourseID]) {
        self.noteIDs = Array(Set(noteIDs)).sorted()
        self.courseIDs = Array(Set(courseIDs)).sorted()
    }
}
