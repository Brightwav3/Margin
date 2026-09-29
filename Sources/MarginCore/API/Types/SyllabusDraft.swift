import Foundation

/// One exam or graded test of a `SyllabusDraft`.
public struct SyllabusExam: Codable, Sendable, Hashable {
    public var title: String
    public var date: LocalDate
    public var time: LocalTime?
    /// Percentage of the final grade, 0...100.
    public var weightPercent: Int

    public init(title: String, date: LocalDate, time: LocalTime? = nil, weightPercent: Int) {
        self.title = title; self.date = date; self.time = time; self.weightPercent = weightPercent
    }
}

/// What a syllabus says about a course, before the user has accepted it (M10-19): the weekly
/// timetable, the exams and how the grade is made up. The import (an agent or a parser) fills it, the
/// user edits it, `SyllabusService.apply` writes it into the course's `_course.md`.
///
/// A section that is `nil` is left as it is in the course; an empty array clears it.
public struct SyllabusDraft: Codable, Sendable, Hashable {
    public var sessions: [NewSession]?
    public var exams: [SyllabusExam]?
    public var grading: [GradingPart]?

    public init(sessions: [NewSession]? = nil, exams: [SyllabusExam]? = nil, grading: [GradingPart]? = nil) {
        self.sessions = sessions; self.exams = exams; self.grading = grading
    }

    /// The draft that says exactly what `course` says now: the starting point for editing.
    public init(course: Course) {
        self.init(
            sessions: course.sessions.map { NewSession(day: $0.day, start: $0.start, lengthHours: $0.lengthHours, kind: $0.kind, room: $0.room) },
            exams: course.exams.map { SyllabusExam(title: $0.title, date: $0.date, time: $0.time, weightPercent: $0.weightPercent) },
            grading: course.grading)
    }

    /// Sum of the grading weights, `nil` when the draft has no grading section.
    public var gradingTotal: Int? { grading.map { $0.reduce(0) { $0 + $1.weightPercent } } }

    /// Things the user should look at that do not stop the draft from being saved.
    public var warnings: [String] {
        var out: [String] = []
        if let total = gradingTotal, !(grading ?? []).isEmpty, total != 100 { out.append("The grading weights add up to \(total)%, not 100%") }
        if let sessions, sessions.isEmpty { out.append("The timetable is empty") }
        return out
    }
}
