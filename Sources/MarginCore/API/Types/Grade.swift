/// One graded item (`{item, group, score, max, date}` in `_grades.md`).
///
/// A grade with `score == nil` is not graded yet (`date` then is the due/exam date).
/// Invariants: `max > 0` when `score` is set; `weightPercent` is the share of the course grade.
public struct Grade: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var courseID: CourseID
    public var item: String
    /// Grading component from `_course.md` (`Problem sets`), if known.
    public var group: String?
    public var weightPercent: Int?
    public var score: Double?
    public var max: Double?
    public var date: LocalDate?

    public init(id: String, courseID: CourseID, item: String, group: String? = nil,
                weightPercent: Int? = nil, score: Double? = nil, max: Double? = nil, date: LocalDate? = nil) {
        self.id = id; self.courseID = courseID; self.item = item; self.group = group
        self.weightPercent = weightPercent; self.score = score; self.max = max; self.date = date
    }

    /// Score as a percentage, or `nil` when not graded.
    public var percent: Double? {
        guard let score, let max, max > 0 else { return nil }
        return score / max * 100
    }
}

/// Current standing of a course.
public struct GradeSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: CourseID { courseID }
    public var courseID: CourseID
    /// Letter grade (`A−`).
    public var letter: String
    /// Percentage so far, 0…100.
    public var percent: Int

    public init(courseID: CourseID, letter: String, percent: Int) {
        self.courseID = courseID; self.letter = letter; self.percent = percent
    }
}
