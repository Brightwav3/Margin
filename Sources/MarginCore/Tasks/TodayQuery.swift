/// What the Today screen shows.
public struct TodayResult: Sendable, Hashable {
    /// Open tasks due before today, oldest first.
    public var overdue: [TaskItem]
    /// Open tasks due today and exams dated today.
    public var today: [TaskItem]
    /// Today's classes by start time.
    public var sessions: [SessionOccurrence]

    /// Overdue first, then today: the flat list `TaskService.today()` returns.
    public var items: [TaskItem] { overdue + today }
}

/// The Today query (M7-05.B): overdue and due-today work plus today's classes.
///
/// "Today" is the `Clock`'s local calendar day at the moment of `run`, so the answer changes at
/// local midnight, follows a time-zone change and is unaffected by DST (a day is a calendar date,
/// not 24 hours). Labels are recomputed for that day.
///
/// - Done tasks and tasks without a due date are not included.
/// - Exams count only on their day: a past exam is not overdue work.
/// - Order: due date, course id, item id.
public struct TodayQuery: Sendable {
    public let clock: any Clock

    public init(clock: any Clock) { self.clock = clock }

    /// - Parameters:
    ///   - tasks: all tasks (any state, any due date).
    ///   - exams: exams as `TaskItem`s of kind `.exam`.
    ///   - sessions: class occurrences of any days; only today's are kept.
    public func run(tasks: [TaskItem], exams: [TaskItem] = [], sessions: [SessionOccurrence] = []) -> TodayResult {
        let today = clock.today
        func relabelled(_ items: [TaskItem]) -> [TaskItem] {
            items.map { TaskOrdering.relabel($0, today: today) }.sorted(by: TaskOrdering.dueOrder)
        }
        let open = tasks.filter { !$0.done }
        let overdue = open.filter { $0.due.map { $0 < today } ?? false }
        let dueToday = open.filter { $0.due == today } + exams.filter { $0.due == today }
        return TodayResult(
            overdue: relabelled(overdue), today: relabelled(dueToday),
            sessions: sessions.filter { $0.date == today }.sorted {
                ($0.session.start, $0.session.courseID, $0.session.id) < ($1.session.start, $1.session.courseID, $1.session.id)
            })
    }

    /// Today's classes of the semester that contains today (see `ServiceRules.currentSemester`).
    /// Empty when there is no semester or today is outside its weeks.
    public func sessionsToday(semesters: [Semester], courses: [Course]) -> [SessionOccurrence] {
        let today = clock.today
        guard let semester = ServiceRules.currentSemester(semesters, today: today),
              let week = semester.week(of: today),
              let all = try? ServiceRules.occurrences(week: week, semester: semester,
                                                     courses: courses.filter { $0.semester == semester.id })
        else { return [] }
        return all.filter { $0.date == today }
    }
}
