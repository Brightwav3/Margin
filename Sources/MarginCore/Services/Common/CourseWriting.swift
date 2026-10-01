import Foundation

/// Rules of `CourseCatalogWriter` shared by the fixture and the vault implementation, so the two
/// cannot drift (contract §5).
enum CourseWriting {
    /// The schedule of a course created without sessions: one 90 minute lecture, Monday 10:00.
    static let defaultSession = NewSession(day: .monday, start: LocalTime.literal(10, 0), lengthHours: 1.5, kind: "Lecture")

    /// A trimmed, non-empty name of reasonable length.
    static func requireName(_ name: String) throws -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw MarginError.invalid("A course needs a name") }
        guard n.count <= 120 else { throw MarginError.invalid("A course name is at most 120 characters") }
        guard !n.containsLineBreak else { throw MarginError.invalid("A course name is one line") }
        guard !VaultPath.filename(fromTitle: n).isEmpty, !NoteIndex.slug(n).isEmpty else {
            throw MarginError.invalid("A course name needs letters or digits")
        }
        return n
    }

    /// Icons are lower-case name tokens (`eco`, `menu_book`, `chart-line`) or one emoji (`🎬`);
    /// palette keys must exist.
    static func requireStyle(icon: String?, color: String?) throws {
        if let icon {
            let token = !icon.isEmpty && icon.count <= 40
                && icon.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }
            guard token || CoursePalette.isEmoji(icon) else {
                throw MarginError.invalid("'\(icon)' is not an icon name (lower-case letters, digits, _ and -) or one emoji")
            }
        }
        if let color, !CoursePalette.keys.contains(color) {
            throw MarginError.invalid("Unknown palette key '\(color)' (\(CoursePalette.keys.joined(separator: ", ")))")
        }
    }

    /// Slug of `name`, made unique against `taken` by a numeric suffix.
    static func courseID(for name: String, taken: Set<CourseID>) -> CourseID {
        let base = NoteIndex.slug(name)
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// The course a `NewCourse` becomes. `usedColors` are the palette keys of the semester's courses.
    static func makeCourse(_ new: NewCourse, id: CourseID, name: String, usedColors: [String]) throws -> Course {
        try requireStyle(icon: new.icon, color: new.color)
        let made = try makeSessions(new.sessions.isEmpty ? [defaultSession] : new.sessions, course: id, defaultRoom: new.room)
        let keys = CoursePalette.orderedKeys
        let color = new.color ?? keys.first { !usedColors.contains($0) } ?? keys[usedColors.count % keys.count]
        return Course(
            id: id, semester: new.semester, name: name, code: new.code.trimmingCharacters(in: .whitespaces),
            professor: new.professor, room: new.room, faculty: new.faculty, credits: new.credits,
            style: CoursePalette.style(icon: new.icon ?? "school", color: color), sessions: made)
    }

    /// Sessions of a course from the dialog's rows: length over 0 and at most 12 hours, no two at the
    /// same day and time, an empty kind is a lecture.
    static func makeSessions(_ sessions: [NewSession], course id: CourseID, defaultRoom: String?) throws -> [Session] {
        var made: [Session] = []
        for s in sessions {
            guard s.lengthHours > 0, s.lengthHours <= 12 else {
                throw MarginError.invalid("A session lasts more than 0 and at most 12 hours, not \(s.lengthHours)")
            }
            let room = s.room.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? defaultRoom
            let session = Session(courseID: id, day: s.day, start: s.start, lengthHours: s.lengthHours,
                                  kind: s.kind.trimmingCharacters(in: .whitespaces).isEmpty ? "Lecture" : s.kind, room: room)
            guard !made.contains(where: { $0.id == session.id }) else {
                throw MarginError.invalid("Two sessions on \(s.day.rawValue) at \(s.start)")
            }
            made.append(session)
        }
        return made
    }

    /// Exams of a course: a title and a weight of 0–100.
    static func makeExams(_ exams: [NewExam], course id: CourseID) throws -> [Exam] {
        try exams.map { e in
            let title = e.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { throw MarginError.invalid("An exam needs a title") }
            guard (0...100).contains(e.weightPercent) else {
                throw MarginError.invalid("An exam weighs 0–100 %, not \(e.weightPercent)")
            }
            return Exam(courseID: id, title: title, date: e.date, time: e.time, weightPercent: e.weightPercent)
        }
    }

    /// The course with `update` applied (fields that are `nil` stay).
    static func applying(_ update: CourseUpdate, to course: Course) throws -> Course {
        var c = course
        func text(_ s: String?) -> String? { s.map { $0.trimmingCharacters(in: .whitespaces) } }
        if let code = text(update.code) { c.code = code }
        if let p = text(update.professor) { c.professor = p.isEmpty ? nil : p }
        if let r = text(update.room) { c.room = r.isEmpty ? nil : r }
        if let f = text(update.faculty) { c.faculty = f.isEmpty ? nil : f }
        if let credits = update.credits {
            guard (0...60).contains(credits) else { throw MarginError.invalid("Credits are 0–60, not \(credits)") }
            c.credits = credits == 0 ? nil : credits
        }
        if let sessions = update.sessions { c.sessions = try makeSessions(sessions, course: c.id, defaultRoom: nil) }
        if let exams = update.exams { c.exams = try makeExams(exams, course: c.id) }
        return c
    }

    /// Checks `override` against its course and semester.
    static func validate(_ override: SessionOverride, course: Course, semester: Semester) throws {
        guard let session = course.sessions.first(where: { $0.id == override.sessionID }) else {
            throw MarginError.notFound("No session \(override.sessionID) in \(course.id)")
        }
        guard override.originalDate.weekday == session.day else {
            throw MarginError.invalid("\(override.originalDate) is a \(override.originalDate.weekday.rawValue), the session is on \(session.day.rawValue)")
        }
        guard semester.week(of: override.originalDate) != nil else {
            throw MarginError.invalid("\(override.originalDate) is outside \(semester.name)")
        }
        if !override.cancelled, override.newStart == nil, override.newRoom == nil {
            throw MarginError.invalid("The override changes nothing (no cancel, new time or new room)")
        }
        if let room = override.newRoom, room.trimmingCharacters(in: .whitespaces).isEmpty {
            throw MarginError.invalid("An empty room is not a room")
        }
    }

    /// `overrides` with `new` in place of the one for the same session and day, sorted by day, then id.
    static func upserting(_ new: SessionOverride, into overrides: [SessionOverride]) -> [SessionOverride] {
        sorted(overrides.filter { $0.id != new.id } + [new])
    }

    static func sorted(_ overrides: [SessionOverride]) -> [SessionOverride] {
        overrides.sorted { ($0.originalDate, $0.sessionID) < ($1.originalDate, $1.sessionID) }
    }
}
