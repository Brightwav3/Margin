/// A study term (`Fall 2026`).
///
/// Invariants: `start` is a Monday, `end >= start`, `breakWeeks` are 1-based week numbers
/// within `1...weekCount`. Week 1 is the ISO week containing `start`.
///
/// An archived semester (`isArchived`) lives in `_archive/` and is read-only.
public struct Semester: Codable, Sendable, Hashable, Identifiable {
    public let id: SemesterID
    public var name: String
    /// First day of week 1 (a Monday).
    public var start: LocalDate
    /// Last day of the term (inclusive), usually the end of the exam period.
    public var end: LocalDate
    /// Weeks without teaching (1-based), e.g. a reading week. They still count as weeks.
    public var breakWeeks: [Int]
    /// Moved to `_archive/`, read-only (`CourseCatalogWriter.setArchived`). Stored as `"archived": true`
    /// in `.margin/semesters.json`; absent means `false`.
    public var isArchived: Bool

    public init(id: SemesterID, name: String, start: LocalDate, end: LocalDate, breakWeeks: [Int] = [],
                isArchived: Bool = false) {
        self.id = id; self.name = name; self.start = start; self.end = end; self.breakWeeks = breakWeeks
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey { case id, name, start, end, breakWeeks, archived }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(SemesterID.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  start: try c.decode(LocalDate.self, forKey: .start), end: try c.decode(LocalDate.self, forKey: .end),
                  breakWeeks: try c.decodeIfPresent([Int].self, forKey: .breakWeeks) ?? [],
                  isArchived: try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end)
        try c.encode(breakWeeks, forKey: .breakWeeks)
        if isArchived { try c.encode(true, forKey: .archived) }
    }

    /// Number of (possibly partial) weeks the term spans.
    public var weekCount: Int { start.startOfWeek.days(to: end.startOfWeek) / 7 + 1 }

    /// 1-based week number of `date`, or `nil` when it is outside the term.
    public func week(of date: LocalDate) -> Int? {
        guard date >= start, date <= end else { return nil }
        return start.startOfWeek.days(to: date) / 7 + 1
    }
}
