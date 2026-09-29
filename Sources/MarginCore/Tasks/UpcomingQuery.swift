/// One calendar day of the Upcoming screen.
public struct UpcomingDay: Sendable, Hashable, Identifiable {
    public var id: LocalDate { date }
    public var date: LocalDate
    public var items: [TaskItem]
}

/// What the Upcoming screen shows.
public struct UpcomingResult: Sendable, Hashable {
    /// The next days (tomorrow first) that have tasks, one group per day.
    public var days: [UpcomingDay]
    /// Tasks due after the listed days and up to the end of this week (Sunday).
    public var thisWeek: [TaskItem]
    /// Tasks due after this week.
    public var later: [TaskItem]
    /// Exams dated after today, soonest first (shown as cards, not as tasks).
    public var exams: [TaskItem]

    /// Every item once, sorted like `TaskService.upcoming()`: due date, course id, item id, with
    /// exams among the tasks.
    public var items: [TaskItem] {
        (days.flatMap(\.items) + thisWeek + later + exams).sorted(by: TaskOrdering.dueOrder)
    }
}

/// The Upcoming query (M7-06.B): open work due after today, grouped for display.
///
/// With `daysAhead = 3` and today Monday 28 Sep: `days` are Tue 29, Wed 30, Thu 1 Oct (only the
/// ones with tasks); `thisWeek` is Fri 2 to Sun 4; `later` is everything after. When the week ends
/// before the listed days do (today is Saturday), `thisWeek` is empty and days run into next week.
/// Done tasks, tasks without a due date, and overdue or today's tasks (that is `TodayQuery`) are
/// left out. Exams have their own group and are not repeated in the others.
public struct UpcomingQuery: Sendable {
    public let clock: any Clock
    /// How many days after today get a group of their own (at least 0).
    public let daysAhead: Int

    public init(clock: any Clock, daysAhead: Int = 3) {
        self.clock = clock; self.daysAhead = max(0, daysAhead)
    }

    public func run(tasks: [TaskItem], exams: [TaskItem] = []) -> UpcomingResult {
        let today = clock.today
        let lastDayGroup = today.adding(days: daysAhead)
        let endOfWeek = today.startOfWeek.adding(days: 6)
        func relabelled(_ items: [TaskItem]) -> [TaskItem] {
            items.map { TaskOrdering.relabel($0, today: today) }.sorted(by: TaskOrdering.dueOrder)
        }
        let open = tasks.filter { !$0.done && ($0.due.map { $0 > today } ?? false) }

        var perDay: [LocalDate: [TaskItem]] = [:]
        var week: [TaskItem] = [], later: [TaskItem] = []
        for t in open {
            guard let due = t.due else { continue }
            if due <= lastDayGroup { perDay[due, default: []].append(t) }
            else if due <= endOfWeek { week.append(t) }
            else { later.append(t) }
        }
        return UpcomingResult(
            days: perDay.keys.sorted().map { UpcomingDay(date: $0, items: relabelled(perDay[$0] ?? [])) },
            thisWeek: relabelled(week), later: relabelled(later),
            exams: relabelled(exams.filter { $0.due.map { $0 > today } ?? false }))
    }
}
