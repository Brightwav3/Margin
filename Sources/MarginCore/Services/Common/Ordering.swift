import Foundation

/// The observable ordering and selection rules shared by the fixture and vault services. They live
/// in one place so the two implementations cannot drift (contract §5); the conformance tests
/// check the results, not the code.
enum ServiceRules {
    // MARK: Courses

    static func sortCourses(_ courses: [Course]) -> [Course] {
        courses.sorted { a, b in
            let (x, y) = (a.name.lowercased(), b.name.lowercased())
            return x != y ? x < y : a.id < b.id
        }
    }

    /// Case-insensitive substring of name, code or professor; `nil`/blank matches everything.
    static func matches(_ course: Course, query: String?) -> Bool {
        guard let q = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !q.isEmpty else { return true }
        return [course.name, course.code, course.professor ?? ""].contains { $0.lowercased().contains(q) }
    }

    /// The semester that contains `today`, else the latest one that started, else the first.
    static func currentSemester(_ semesters: [Semester], today: LocalDate) -> Semester? {
        semesters.first { today >= $0.start && today <= $0.end }
            ?? semesters.filter { $0.start <= today }.max { $0.start < $1.start }
            ?? semesters.min { $0.start < $1.start }
    }

    /// The classes of a 1-based `week` of `semester`, sorted by date, start time, course id. `overrides`
    /// (of the courses in `courses`) are applied: a cancelled class stays, flagged; a moved one shows at
    /// its new day, time and room, and only in the week that contains its new day.
    static func occurrences(week: Int, semester: Semester, courses: [Course],
                            overrides: [SessionOverride] = []) throws -> [SessionOccurrence] {
        guard week >= 1, week <= semester.weekCount else {
            throw MarginError.invalid("Week \(week) is outside \(semester.name) (1…\(semester.weekCount))")
        }
        let monday = semester.start.startOfWeek.adding(days: (week - 1) * 7)
        let sunday = monday.adding(days: 6)
        func inWeek(_ d: LocalDate) -> Bool { d >= monday && d <= sunday }
        let byKey = Dictionary(overrides.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        var result: [SessionOccurrence] = []
        for course in courses {
            for session in course.sessions {
                let date = monday.adding(days: session.day.isoNumber - 1)
                guard let o = byKey["\(session.id)@\(date.iso)"], o.courseID == course.id else {
                    result.append(SessionOccurrence(session: session, date: date))
                    continue
                }
                if let placed = apply(o, to: session), inWeek(placed.date) { result.append(placed) }
            }
        }
        // Classes moved here from another week.
        let sessions = Dictionary(courses.flatMap { $0.sessions }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for o in overrides where !o.cancelled && !inWeek(o.originalDate) {
            if let session = sessions[o.sessionID], let placed = apply(o, to: session), inWeek(placed.date) {
                result.append(placed)
            }
        }
        return result.sorted {
            ($0.date, $0.session.start, $0.session.courseID, $0.session.id)
                < ($1.date, $1.session.start, $1.session.courseID, $1.session.id)
        }
    }

    /// The occurrence `override` makes of `session`.
    private static func apply(_ o: SessionOverride, to session: Session) -> SessionOccurrence? {
        var s = session
        if !o.cancelled {
            if let start = o.newStart { s.start = start.time }
            if let room = o.newRoom { s.room = room }
        }
        return SessionOccurrence(session: s, date: o.cancelled ? o.originalDate : (o.newStart?.date ?? o.originalDate),
                                 originalDate: o.originalDate, isCancelled: o.cancelled, note: o.note)
    }

    // MARK: Notes

    /// Dated notes first (newest date first), then undated; ties by title, then id.
    static func sortNotes(_ notes: [NoteSummary]) -> [NoteSummary] {
        notes.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?) where x != y: return x > y
            case (.some, .none): return true
            case (.none, .some): return false
            default:
                let (x, y) = (a.title.lowercased(), b.title.lowercased())
                return x != y ? x < y : a.id < b.id
            }
        }
    }

    /// `<course>/<slug of title>`, the id of a note created through `NoteRepository.create`.
    static func noteID(course: CourseID, title: String) -> NoteID {
        let slug = NoteIndex.slug(title)
        return "\(course)/\(slug.isEmpty ? "untitled" : slug)"
    }

    /// The body of a new note: the caller's text, or a bare heading.
    static func initialBody(title: String, text: String) -> String {
        text.isEmpty ? "# \(title)\n" : text
    }

    /// Vault-relative path of a note (`<semester>/<course>/<title>.md`).
    static func notePath(semester: Semester, course: Course, fileTitle: String) -> String {
        [semester.name, VaultPath.filename(fromTitle: course.name), VaultPath.filename(fromTitle: fileTitle) + ".md"]
            .joined(separator: "/")
    }

    // MARK: Tasks

    /// Exams as due items (`kind == .exam`).
    static func examItems(_ courses: [Course]) -> [TaskItem] {
        courses.flatMap { course in
            course.exams.map { exam in
                TaskItem(id: "exam-\(exam.id)", text: exam.title, due: exam.date, label: nil, done: false, kind: .exam,
                         source: TaskLocation(noteID: "\(course.id)/_course", line: 1, courseID: course.id))
            }
        }
    }

    static func relabel(_ item: TaskItem, today: LocalDate) -> TaskItem { TaskOrdering.relabel(item, today: today) }

    /// Open tasks due today or earlier, exams dated today (see `TodayQuery`).
    static func todayItems(tasks: [TaskItem], exams: [TaskItem], clock: any Clock) -> [TaskItem] {
        TodayQuery(clock: clock).run(tasks: tasks, exams: exams).items
    }

    /// Open tasks and exams due after today (see `UpcomingQuery`).
    static func upcomingItems(tasks: [TaskItem], exams: [TaskItem], clock: any Clock) -> [TaskItem] {
        UpcomingQuery(clock: clock).run(tasks: tasks, exams: exams).items
    }

    /// All tasks of a course sorted by note id, then line; labels recomputed for `today`.
    static func courseTasks(_ tasks: [TaskItem], today: LocalDate) -> [TaskItem] {
        tasks.map { relabel($0, today: today) }.sorted {
            $0.source.noteID != $1.source.noteID ? $0.source.noteID < $1.source.noteID : $0.source.line < $1.source.line
        }
    }
}
