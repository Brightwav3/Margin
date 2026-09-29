/// Where a task lives in the vault: note and 1-based line.
///
/// Invariant: `line >= 1`. `courseID` is denormalised for grouping.
public struct TaskLocation: Codable, Sendable, Hashable {
    public var noteID: NoteID
    public var line: Int
    public var courseID: CourseID?

    public init(noteID: NoteID, line: Int, courseID: CourseID? = nil) {
        self.noteID = noteID; self.line = line; self.courseID = courseID
    }
}

/// Relative description of a due date, computed against the `Clock`'s today.
public enum DueLabel: Codable, Sendable, Hashable {
    case overdue(days: Int)
    case today
    case tomorrow
    /// 2…6 days ahead.
    case weekday(Weekday)
    /// 7 or more days ahead.
    case date(LocalDate)

    /// Label for `due` when today is `today`.
    public static func make(due: LocalDate, today: LocalDate) -> DueLabel {
        let d = today.days(to: due)
        switch d {
        case ..<0: return .overdue(days: -d)
        case 0: return .today
        case 1: return .tomorrow
        case 2...6: return .weekday(due.weekday)
        default: return .date(due)
        }
    }
}

/// What a due item is.
public enum TaskKind: String, Codable, Sendable, Hashable {
    case task
    /// An exam shown among due items (derived from `Exam`).
    case exam
}

/// A task (`- [ ] text 📅 2026-10-01`) or an exam shown among due items.
///
/// `label` is derived from `due` at creation time; recompute with `DueLabel.make` after the
/// clock moves. `id` is stable while the task text/location is unchanged.
public struct TaskItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var text: String
    public var due: LocalDate?
    public var label: DueLabel?
    public var done: Bool
    public var kind: TaskKind
    public var source: TaskLocation

    public init(id: String, text: String, due: LocalDate? = nil, label: DueLabel? = nil,
                done: Bool = false, kind: TaskKind = .task, source: TaskLocation) {
        self.id = id; self.text = text; self.due = due; self.label = label
        self.done = done; self.kind = kind; self.source = source
    }
}
