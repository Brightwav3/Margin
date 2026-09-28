/// An exam or graded test (`exams: - {title: Midterm, date: 2026-10-01, weight: 25%}`).
///
/// `time` is optional (the vault often has only a date). Invariant: `weightPercent` in 0…100.
public struct Exam: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(courseID)-\(date.iso)-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))" }
    public var courseID: CourseID
    public var title: String
    public var date: LocalDate
    public var time: LocalTime?
    public var weightPercent: Int

    public init(courseID: CourseID, title: String, date: LocalDate, time: LocalTime? = nil, weightPercent: Int) {
        self.courseID = courseID; self.title = title; self.date = date
        self.time = time; self.weightPercent = weightPercent
    }
}
