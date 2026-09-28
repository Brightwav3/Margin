/// A due token written after `@` in a task (`@2026-10-02`, `@Tue`, `@today`, `@before-midterm`).
/// Parsing is independent of the clock; resolution to a date is done by `DueResolver`.
public enum DueToken: Sendable, Hashable {
    case iso(LocalDate)
    case weekday(Weekday)
    case today
    case tomorrow
    /// Monday of the next ISO week (Monday-based weeks, same as `Clock.calendar`).
    case nextWeek
    case beforeMidterm
    case beforeExam
    case beforeLecture

    /// Parses the word after `@` (case-insensitive). Returns `nil` for anything else, including
    /// impossible ISO dates such as `2026-02-30`.
    public init?(word: String) {
        let w = word.lowercased()
        switch w {
        case "today": self = .today
        case "tomorrow": self = .tomorrow
        case "next-week": self = .nextWeek
        case "before-midterm": self = .beforeMidterm
        case "before-exam": self = .beforeExam
        case "before-lecture": self = .beforeLecture
        default:
            if let d = LocalDate(iso: w) {
                self = .iso(d)
            } else if let wd = Weekday(token: w) {
                self = .weekday(wd)
            } else {
                return nil
            }
        }
    }
}

/// Course data needed to resolve `@before-…` tokens. Injected so the extractor stays pure.
public struct CourseEventContext: Sendable, Hashable {
    public var exams: [Exam]
    public var sessions: [Session]

    public init(exams: [Exam] = [], sessions: [Session] = []) {
        self.exams = exams; self.sessions = sessions
    }

    public static let empty = CourseEventContext()
}

/// Resolves due tokens to calendar days relative to a `Clock`.
///
/// Semantics (documented decisions):
/// - `@Tue` / `@tuesday`: the nearest day strictly after today with that weekday. On a Tuesday it
///   is next Tuesday; today is written `@today`.
/// - `@next-week`: Monday of the next week (the Monday after the current week's Monday).
/// - `@before-midterm`: the day before the earliest exam whose title contains "midterm"
///   (case-insensitive) and whose date is strictly after today.
/// - `@before-exam`: the day before the earliest exam (any title) strictly after today.
/// - `@before-lecture`: the day before the next occurrence, strictly after today, of the
///   earliest session whose kind is "Lecture" (case-insensitive). Session overrides are ignored.
/// - Course events resolve to `nil` when the context has no matching future event.
public struct DueResolver: Sendable {
    public let clock: any Clock
    public let context: CourseEventContext

    public init(clock: any Clock, context: CourseEventContext = .empty) {
        self.clock = clock; self.context = context
    }

    public func resolve(_ token: DueToken) -> LocalDate? {
        let today = clock.today
        switch token {
        case .iso(let d): return d
        case .today: return today
        case .tomorrow: return today.adding(days: 1)
        case .nextWeek: return today.startOfWeek.adding(days: 7)
        case .weekday(let wd):
            var diff = (wd.isoNumber - today.weekday.isoNumber + 7) % 7
            if diff == 0 { diff = 7 }
            return today.adding(days: diff)
        case .beforeMidterm:
            return nextExam { $0.title.lowercased().contains("midterm") }
        case .beforeExam:
            return nextExam { _ in true }
        case .beforeLecture:
            let days = context.sessions
                .filter { $0.kind.lowercased() == "lecture" }
                .map { s -> LocalDate in
                    var diff = (s.day.isoNumber - today.weekday.isoNumber + 7) % 7
                    if diff == 0 { diff = 7 }
                    return today.adding(days: diff)
                }
            return days.min().map { $0.adding(days: -1) }
        }
    }

    private func nextExam(where match: (Exam) -> Bool) -> LocalDate? {
        let today = clock.today
        return context.exams.filter { match($0) && $0.date > today }
            .map(\.date).min().map { $0.adding(days: -1) }
    }
}
