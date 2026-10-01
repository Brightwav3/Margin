import MarginCore
import Observation
import SwiftUI

/// One card of the 2c gallery: a note, or a class of the timetable that has no note yet.
public struct LectureCardData: Identifiable, Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        case note(NoteSummary)
        case upcoming(SessionOccurrence)
    }

    public var id: String
    public var source: Source
    /// „Thu 24 Sep“; for undated notes the day they were last edited.
    public var date: String
    /// „Lecture 8“, „Lab 2“, „Study note“.
    public var kind: String
    /// „Cell membrane“.
    public var theme: String
    /// „412 words“, „3 images“, „Tomorrow · Sci 204“.
    public var meta: String
    public var badge: (text: String, tone: Badge.Tone)?
    public var isUpcoming: Bool
    public var filter: CourseDetailModel.Filter
    /// Sort key: class date, else last edit.
    var sortDate: LocalDate

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.meta == b.meta && a.badge?.text == b.badge?.text }
    public func hash(into h: inout Hasher) { h.combine(id) }

    public var note: NoteSummary? { if case .note(let n) = source { n } else { nil } }
}

/// A row of the course pages Tasks and Exam prep, and of Coming up in the inspector.
public struct CourseTaskRow: Identifiable, Sendable, Hashable {
    public var id: String { task.id }
    public var task: TaskItem
    /// Weight of the graded item with the same name („15%“).
    public var weight: String?
    /// Graded result („Graded 18/20“), replaces the due label when present.
    public var graded: String?
    /// Title of the note the task lives in („Lecture 8“).
    public var from: String?
}

/// Course detail (2c) and its pages: gallery of lecture notes, tasks, exam prep, grades.
@MainActor @Observable
public final class CourseDetailModel {
    public enum Page: String, CaseIterable, Sendable {
        case gallery, tasks, examPrep, grades

        public var title: String {
            switch self {
            case .gallery: "Gallery"
            case .tasks: "Tasks"
            case .examPrep: "Exam prep"
            case .grades: "Grades"
            }
        }

        var icon: String {
            switch self {
            case .gallery: "grid_view"
            case .tasks: "check_box"
            case .examPrep: "quiz"
            case .grades: "bar_chart"
            }
        }
    }

    public enum Filter: String, CaseIterable, Sendable {
        case all, lectures, labs, study

        public var title: String {
            switch self {
            case .all: "All"
            case .lectures: "Lectures"
            case .labs: "Labs"
            case .study: "Study notes"
            }
        }

        static func of(_ kind: NoteKind) -> Filter {
            switch kind {
            case .lecture, .seminar: .lectures
            case .lab, .tutorial: .labs
            case .study, .note: .study
            }
        }
    }

    public let courseID: CourseID
    public var page: Page = .gallery
    public var filter: Filter = .all
    public var newestFirst = true
    public var selected: String?

    public private(set) var course: Course?
    public private(set) var grade: GradeSummary?
    public private(set) var grades: [Grade] = []
    public private(set) var cards: [LectureCardData] = []
    public private(set) var tasks: [TaskItem] = []
    public private(set) var notes: [NoteSummary] = []
    public private(set) var upcoming: [SessionOccurrence] = []
    public private(set) var sessionCount = 0
    public private(set) var isLoaded = false

    private let env: AppEnvironment

    public init(env: AppEnvironment, course: CourseID) {
        self.env = env
        self.courseID = course
    }

    var today: LocalDate { env.clock.today }

    public func load() async {
        do {
            let course = try await env.courses.course(id: courseID)
            self.course = course
            grade = try await env.grades.average(course: courseID)
            grades = try await env.grades.grades(course: courseID)
            notes = try await env.notes.notes(course: courseID)
            tasks = try await env.tasks.tasks(course: courseID)
            let semesters = try await env.courses.semesters()
            let semester = semesters.first { $0.id == course.semester }
            let week = semester.flatMap { env.clock.weekOfSemester($0) }
            var next: [SessionOccurrence] = []
            if let week, let semester {
                for w in [week, week + 1] where w <= semester.weekCount {
                    next += try await env.courses.sessions(week: w)
                }
                sessionCount = course.sessions.count * max(0, semester.weekCount - semester.breakWeeks.count)
            }
            let now = env.clock.localNow
            upcoming = next.filter { $0.session.courseID == courseID && !$0.isCancelled && $0.start >= now }
                .sorted { $0.start < $1.start }
            cards = buildCards()
            if selected == nil { selected = visibleCards.first { !$0.isUpcoming }?.id }
        } catch {
            course = course ?? nil
        }
        isLoaded = true
    }

    /// Reloads when notes change on disk (another editor, the vault watcher).
    public func observeNotes() async {
        for await _ in env.notes.externalChanges where ExternalChanges.followed { await load() }
    }

    /// Reloads when tasks change (toggled here, in Today or in a note).
    public func observeTasks() async {
        for await _ in env.tasks.updates { await load() }
    }

    // MARK: Gallery

    private func buildCards() -> [LectureCardData] {
        var result: [LectureCardData] = []
        let datedNotes = Set(notes.compactMap(\.date))
        for note in notes where note.title != "Assignments" {
            let (kind, theme) = Self.split(note)
            let date = note.date ?? note.modified?.date ?? today
            let upcomingClass = note.isPlaceholder || (note.date.map { $0 >= today } ?? false) && note.wordCount == 0
            var meta: String
            if upcomingClass, let occurrence = upcoming.first(where: { $0.date == note.date }) {
                meta = Self.relative(occurrence.date, today: today)
                if let room = occurrence.session.room ?? course?.room { meta += " · \(room)" }
            } else if note.imageCount > 0 && note.wordCount < 50 {
                meta = note.imageCount == 1 ? "1 image" : "\(note.imageCount) images"
            } else {
                meta = "\(note.wordCount) words"
            }
            var badge: (String, Badge.Tone)?
            if note.openTasks > 0 { badge = ("\(note.openTasks) open", .warning) }
            else if note.totalTasks > 0 { badge = ("Done", .success) }
            result.append(LectureCardData(
                id: note.id, source: .note(note), date: Self.day(date), kind: kind, theme: theme, meta: meta,
                badge: badge, isUpcoming: upcomingClass, filter: note.date == nil ? .study : Filter.of(note.kind),
                sortDate: date))
        }
        // The next class without a note: a card that becomes its note when written in.
        if let occurrence = upcoming.first(where: { !datedNotes.contains($0.date) }),
           !result.contains(where: { $0.isUpcoming }) {
            var meta = Self.relative(occurrence.date, today: today)
            if let room = occurrence.session.room ?? course?.room { meta += " · \(room)" }
            let same = notes.filter { Self.split($0).0.hasPrefix(occurrence.session.kind) }.count
            result.append(LectureCardData(
                id: occurrence.id, source: .upcoming(occurrence), date: Self.day(occurrence.date),
                kind: "\(occurrence.session.kind) \(same + 1)", theme: "Not started",
                meta: meta, badge: nil, isUpcoming: true,
                filter: CoursesOverviewModel.KindGroup.of(kind: occurrence.session.kind) == .labs ? .labs : .lectures,
                sortDate: occurrence.date))
        }
        return result
    }

    public var visibleCards: [LectureCardData] {
        let kept = cards.filter { filter == .all || $0.filter == filter }
        return kept.sorted { a, b in
            if a.sortDate != b.sortDate { return newestFirst ? a.sortDate > b.sortDate : a.sortDate < b.sortDate }
            return a.theme < b.theme
        }
    }

    /// „Lecture 8 — Cell membrane“ → („Lecture 8“, „Cell membrane“); other titles keep the kind.
    nonisolated static func split(_ note: NoteSummary) -> (String, String) {
        if let range = note.title.range(of: " — ") {
            return (String(note.title[..<range.lowerBound]), String(note.title[range.upperBound...]))
        }
        let kind: String = switch note.kind {
        case .lecture: "Lecture"
        case .lab: "Lab"
        case .seminar: "Seminar"
        case .tutorial: "Tutorial"
        case .study: "Study note"
        case .note: "Note"
        }
        return (kind, note.title)
    }

    nonisolated static func day(_ d: LocalDate) -> String {
        "\(CoursesFormat.weekday(d.weekday)) \(d.day) \(CoursesFormat.month(d.month))"
    }

    nonisolated static func relative(_ d: LocalDate, today: LocalDate) -> String {
        switch today.days(to: d) {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: day(d)
        }
    }

    /// „BIO 201 · Dr. Okafor · 30 sessions · A− 91%“.
    public var subtitle: String {
        guard let course else { return "" }
        var parts = [course.code]
        if let p = course.professor { parts.append(p) }
        if sessionCount > 0 { parts.append("\(sessionCount) sessions") }
        if let grade { parts.append("\(grade.letter) \(grade.percent)%") }
        return parts.joined(separator: " · ")
    }

    // MARK: Tasks and exam prep

    private func row(_ task: TaskItem) -> CourseTaskRow {
        let grade = grades.first { $0.item.caseInsensitiveCompare(task.text) == .orderedSame }
        let graded = grade.flatMap { g in g.score.map { s in "Graded \(Self.number(s))/\(Self.number(g.max ?? 0))" } }
        let from = notes.first { $0.id == task.source.noteID }.map { Self.split($0).0 }
        return CourseTaskRow(task: task, weight: grade?.weightPercent.map { "\($0)%" }, graded: graded, from: from)
    }

    nonisolated static func number(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// Tasks of the course's Assignments note, open first by due date.
    public var assignments: [CourseTaskRow] {
        tasks.filter { $0.kind == .task && isAssignment($0) }.sorted(by: Self.order).map(row)
    }

    /// Tasks written in lecture and study notes (what to do before the exams), plus the exams.
    public var examPrep: [CourseTaskRow] {
        tasks.filter { $0.kind == .exam || !isAssignment($0) }.sorted(by: Self.order).map(row)
    }

    private func isAssignment(_ task: TaskItem) -> Bool {
        notes.first { $0.id == task.source.noteID }?.title == "Assignments"
    }

    nonisolated static func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.done != b.done { return !a.done }
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.text < b.text
        }
    }

    public var openTaskCount: Int { tasks.filter { !$0.done && $0.kind == .task }.count }

    // MARK: Inspector: Coming up

    public struct ComingUp: Identifiable, Sendable {
        public var id: String
        public var title: String
        public var meta: String
        public var icon: String
        public var distance: String
        var date: LocalDate
        public var target: Target
        public enum Target: Sendable { case task(TaskItem), session(SessionOccurrence) }
    }

    public var comingUp: [ComingUp] {
        var items: [ComingUp] = []
        for task in tasks where !task.done {
            guard let due = task.due, due >= today else { continue }
            let weight = row(task).weight.map { " · \($0)" } ?? ""
            items.append(ComingUp(id: task.id, title: task.text, meta: "\(Self.day(due))\(weight)",
                                  icon: task.kind == .exam ? "quiz" : "assignment",
                                  distance: "\(today.days(to: due))d", date: due, target: .task(task)))
        }
        // Exams and graded items with a date (Midterm, Problem set 3) that are not tasks already.
        var titles = Set(items.map { $0.title.lowercased() })
        for exam in course?.exams ?? [] where exam.date >= today && !titles.contains(exam.title.lowercased()) {
            titles.insert(exam.title.lowercased())
            let task = TaskItem(id: exam.id, text: exam.title, due: exam.date,
                                label: DueLabel.make(due: exam.date, today: today), done: false, kind: .exam,
                                source: TaskLocation(noteID: "", line: 0, courseID: courseID))
            items.append(ComingUp(id: exam.id, title: exam.title, meta: "\(Self.day(exam.date)) · \(exam.weightPercent)%",
                                  icon: "quiz", distance: "\(today.days(to: exam.date))d", date: exam.date,
                                  target: .task(task)))
        }
        for grade in grades where grade.score == nil {
            guard let date = grade.date, date >= today, !titles.contains(grade.item.lowercased()) else { continue }
            titles.insert(grade.item.lowercased())
            let task = TaskItem(id: grade.id, text: grade.item, due: date, label: DueLabel.make(due: date, today: today),
                                done: false, kind: .task, source: TaskLocation(noteID: "", line: 0, courseID: courseID))
            let weight = grade.weightPercent.map { " · \($0)%" } ?? ""
            items.append(ComingUp(id: grade.id, title: grade.item, meta: "\(Self.day(date))\(weight)",
                                  icon: "assignment", distance: "\(today.days(to: date))d", date: date, target: .task(task)))
        }
        if let next = upcoming.first {
            let title = notes.first { $0.date == next.date }?.title ?? next.session.kind
            var meta = "\(Self.day(next.date)) · \(CoursesFormat.hour(next.session.start))"
            if let room = next.session.room ?? course?.room { meta += " · \(room)" }
            items.append(ComingUp(id: next.id, title: title, meta: meta, icon: "event_upcoming",
                                  distance: "\(today.days(to: next.date))d", date: next.date, target: .session(next)))
        }
        return items.sorted { $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date }
    }

    /// „Tue, Thu 10:00 · Sci 204“.
    public var sessionsLine: String {
        guard let course, !course.sessions.isEmpty else { return "No sessions" }
        let days = course.sessions.map { CoursesFormat.weekday($0.day) }
        let times = Set(course.sessions.map { CoursesFormat.hour($0.start) })
        var line = days.joined(separator: ", ")
        if times.count == 1, let t = times.first { line += " \(t)" }
        if let room = course.room { line += " · \(room)" }
        return line
    }

    // MARK: Writes

    /// Creates an empty study note and returns it.
    public func createNote(title: String = "Untitled", kind: NoteKind = .study, body: String = "") async throws -> NoteSummary? {
        var name = title
        var n = 2
        while notes.contains(where: { $0.title == name }) { name = "\(title) \(n)"; n += 1 }
        let title = name
        let change = try await env.notes.create(course: courseID, title: title, kind: kind, text: "# \(title)\n\n" + body,
                                                actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        await load()
        let created = change.entries.first?.noteID
        return notes.first { $0.id == created } ?? notes.first { $0.title == title }
    }

    public func toggle(_ task: TaskItem) async throws {
        _ = try await env.tasks.toggle(id: task.id, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        await load()
    }
}
