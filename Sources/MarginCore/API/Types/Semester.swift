/// A study term (`Fall 2026`).
///
/// Invariants: `start` is a Monday, `end >= start`, `breakWeeks` are 1-based week numbers
/// within `1...weekCount`. Week 1 is the ISO week containing `start`.
public struct Semester: Codable, Sendable, Hashable, Identifiable {
    public let id: SemesterID
    public var name: String
    /// First day of week 1 (a Monday).
    public var start: LocalDate
    /// Last day of the term (inclusive), usually the end of the exam period.
    public var end: LocalDate
    /// Weeks without teaching (1-based), e.g. a reading week. They still count as weeks.
    public var breakWeeks: [Int]

    public init(id: SemesterID, name: String, start: LocalDate, end: LocalDate, breakWeeks: [Int] = []) {
        self.id = id; self.name = name; self.start = start; self.end = end; self.breakWeeks = breakWeeks
    }

    /// Number of (possibly partial) weeks the term spans.
    public var weekCount: Int { start.startOfWeek.days(to: end.startOfWeek) / 7 + 1 }

    /// 1-based week number of `date`, or `nil` when it is outside the term.
    public func week(of date: LocalDate) -> Int? {
        guard date >= start, date <= end else { return nil }
        return start.startOfWeek.days(to: date) / 7 + 1
    }
}
