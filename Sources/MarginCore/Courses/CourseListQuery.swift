import Foundation

/// Sorting and filtering of the course list (M3-04): a pure function over `[Course]`.
///
/// It is not part of `CourseCatalog.courses(query:)` on purpose: that method takes a plain search
/// string and is a contract type (promoting this query to the API would be a `api` change that needs
/// the human's approval). The UI-side list model applies it to what the catalog returns; the facts
/// it cannot get from a `Course` (open due tasks per course) come in through `Context`.
///
/// Rules:
/// - **Filter:** `faculty` (any of, case-insensitive; a course without faculty never matches a
///   non-empty set), `searchText` (case-insensitive substring of name, code or professor, the same
///   rule as `CourseCatalog.courses(query:)`), `onlyWithDue` (at least one open due task).
///   Filters combine with "and".
/// - **Sort:** by `sortBy`, ascending unless `descending`. Ties are broken by name
///   (case-insensitive), then id, in the same direction. `nextSession` puts courses without any
///   upcoming session last in both directions.
public struct CourseListQuery: Codable, Sendable, Hashable {
    public enum SortKey: String, Codable, Sendable, Hashable, CaseIterable {
        case name, code, nextSession, dueCount
    }

    /// The facts about "now" and about tasks that a query needs.
    public struct Context: Sendable, Hashable {
        /// Current local time (`Clock.localNow`); a session starting exactly now counts as upcoming.
        public var now: LocalDateTime
        /// Open due tasks per course (see `dueCounts(from:)`); missing courses have none.
        public var dueCounts: [CourseID: Int]

        public init(now: LocalDateTime, dueCounts: [CourseID: Int] = [:]) {
            self.now = now; self.dueCounts = dueCounts
        }
    }

    public var sortBy: SortKey
    public var descending: Bool
    public var faculties: Set<String>
    public var searchText: String
    public var onlyWithDue: Bool

    public init(sortBy: SortKey = .name, descending: Bool = false, faculties: Set<String> = [],
                searchText: String = "", onlyWithDue: Bool = false) {
        self.sortBy = sortBy; self.descending = descending; self.faculties = faculties
        self.searchText = searchText; self.onlyWithDue = onlyWithDue
    }

    /// Sorted by name, no filter (the order of `CourseCatalog.courses(query: nil)`).
    public static let `default` = CourseListQuery()

    /// The courses that pass the filters, in the requested order.
    public func apply(to courses: [Course], context: Context) -> [Course] {
        let wanted = Set(faculties.map(Self.fold))
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = courses.filter { course in
            if !wanted.isEmpty {
                guard let faculty = course.faculty, wanted.contains(Self.fold(faculty)) else { return false }
            }
            if onlyWithDue && (context.dueCounts[course.id] ?? 0) == 0 { return false }
            return ServiceRules.matches(course, query: search)
        }

        // Precompute the sort keys once.
        struct Row { var course: Course; var name: String; var next: LocalDateTime?; var due: Int }
        let rows = kept.map {
            Row(course: $0, name: $0.name.lowercased(),
                next: sortBy == .nextSession ? CourseSchedule.nextSession(of: $0, after: context.now) : nil,
                due: context.dueCounts[$0.id] ?? 0)
        }
        func order(_ a: Row, _ b: Row) -> Bool {   // ascending
            switch sortBy {
            case .name: break
            case .code:
                let (x, y) = (a.course.code.lowercased(), b.course.code.lowercased())
                if x != y { return x < y }
            case .dueCount:
                if a.due != b.due { return a.due < b.due }
            case .nextSession:
                if a.next != b.next {
                    guard let x = a.next else { return false }
                    guard let y = b.next else { return true }
                    return x < y
                }
            }
            return a.name != b.name ? a.name < b.name : a.course.id < b.course.id
        }
        let sorted: [Row]
        if !descending {
            sorted = rows.sorted(by: order)
        } else if sortBy == .nextSession {
            // Latest first, but courses without a session stay last.
            sorted = rows.sorted { a, b in
                switch (a.next, b.next) {
                case (nil, nil): return order(b, a)
                case (nil, _): return false
                case (_, nil): return true
                default: return order(b, a)
                }
            }
        } else {
            sorted = rows.sorted { order($1, $0) }
        }
        return sorted.map(\.course)
    }

    /// Open due tasks per course: tasks that are not done, have a due date and belong to a course.
    public static func dueCounts(from tasks: [TaskItem]) -> [CourseID: Int] {
        var counts: [CourseID: Int] = [:]
        for task in tasks where !task.done && task.due != nil {
            if let course = task.source.courseID { counts[course, default: 0] += 1 }
        }
        return counts
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Facts derived from the weekly timetable of a course.
public enum CourseSchedule {
    /// The start of the first weekly session that begins at or after `now` within the next seven
    /// days, `nil` for a course without sessions. Cancellations (`SessionOverride`) are not applied.
    public static func nextSession(of course: Course, after now: LocalDateTime) -> LocalDateTime? {
        nextOccurrence(of: course.sessions, after: now)?.start
    }

    /// The upcoming occurrence of the earliest of `sessions` (see `nextSession(of:after:)`).
    static func nextOccurrence(of sessions: [Session], after now: LocalDateTime) -> SessionOccurrence? {
        var best: SessionOccurrence?
        for session in sessions {
            let ahead = (session.day.isoNumber - now.date.weekday.isoNumber + 7) % 7
            var date = now.date.adding(days: ahead)
            if LocalDateTime(date: date, time: session.start) < now { date = date.adding(days: 7) }
            let candidate = SessionOccurrence(session: session, date: date)
            if let current = best, current.start <= candidate.start { continue }
            best = candidate
        }
        return best
    }
}
