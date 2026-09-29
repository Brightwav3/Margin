import Foundation

/// The rules of `SyllabusService`, shared by the fixture and the vault implementation.
enum SyllabusRules {
    /// The course with the draft's sections in place of its own, in the order the draft gives them.
    /// Validates the draft.
    static func apply(_ draft: SyllabusDraft, to course: Course) throws -> Course {
        var new = course
        if let sessions = draft.sessions { new.sessions = try makeSessions(sessions, course: course.id) }
        if let exams = draft.exams { new.exams = try makeExams(exams, course: course.id) }
        if let grading = draft.grading { new.grading = try makeGrading(grading) }
        return new
    }

    static func makeSessions(_ list: [NewSession], course: CourseID) throws -> [Session] {
        var made: [Session] = []
        for s in list {
            guard s.lengthHours > 0, s.lengthHours <= 12 else {
                throw MarginError.invalid("A session lasts more than 0 and at most 12 hours, not \(s.lengthHours)")
            }
            let session = Session(courseID: course, day: s.day, start: s.start, lengthHours: s.lengthHours,
                                  kind: s.kind.trimmingCharacters(in: .whitespaces).isEmpty ? "Lecture" : s.kind,
                                  room: s.room?.trimmingCharacters(in: .whitespaces).isEmpty == false ? s.room : nil)
            guard !made.contains(where: { $0.id == session.id }) else {
                throw MarginError.invalid("Two sessions on \(s.day.rawValue) at \(s.start)")
            }
            made.append(session)
        }
        return made
    }

    static func makeExams(_ list: [SyllabusExam], course: CourseID) throws -> [Exam] {
        var made: [Exam] = []
        for e in list {
            let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw MarginError.invalid("An exam needs a title") }
            guard !title.contains("\n") else { throw MarginError.invalid("An exam title is one line") }
            guard (0...100).contains(e.weightPercent) else { throw MarginError.invalid("The weight of \(title) must be from 0 to 100") }
            let exam = Exam(courseID: course, title: title, date: e.date, time: e.time, weightPercent: e.weightPercent)
            guard !made.contains(where: { $0.id == exam.id }) else { throw MarginError.invalid("Two exams called \(title) on \(e.date.iso)") }
            made.append(exam)
        }
        return made
    }

    static func makeGrading(_ list: [GradingPart]) throws -> [GradingPart] {
        var made: [GradingPart] = []
        for g in list {
            let label = g.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { throw MarginError.invalid("A grading part needs a label") }
            guard !label.contains("\n") else { throw MarginError.invalid("A grading label is one line") }
            guard (0...100).contains(g.weightPercent) else { throw MarginError.invalid("The weight of \(label) must be from 0 to 100") }
            guard !made.contains(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) else {
                throw MarginError.invalid("Two grading parts called \(label)")
            }
            made.append(GradingPart(label: label, weightPercent: g.weightPercent))
        }
        let total = made.reduce(0) { $0 + $1.weightPercent }
        guard total <= 100 else { throw MarginError.invalid("The grading weights add up to \(total)%, more than 100%") }
        return made
    }
}
