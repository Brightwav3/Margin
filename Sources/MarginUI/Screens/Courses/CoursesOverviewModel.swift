import MarginCore
import Observation
import SwiftUI

/// One course card of 1a: the course plus the facts shown on it.
public struct CourseCardData: Identifiable, Sendable, Hashable {
    public var id: CourseID { course.id }
    public var course: Course
    public var noteCount: Int
    /// Letter grade so far (`A−`), nil before the first graded item.
    public var grade: String?
    /// „Tue 10:00 · Lecture 9 · Membrane transport“; nil for a course without sessions.
    public var next: String?

    /// „14 notes · A−“.
    public var summary: String {
        let notes = noteCount == 1 ? "1 note" : "\(noteCount) notes"
        return grade.map { "\(notes) · \($0)" } ?? notes
    }
}

/// A block of the 1b timetable.
public struct TimetableBlock: Identifiable, Sendable, Hashable {
    public var id: String { occurrence.id }
    public var occurrence: SessionOccurrence
    public var code: String
    public var style: CourseStyle

    /// „Lecture · 10:00“.
    public var detail: String { "\(occurrence.session.kind) · \(CoursesFormat.hour(occurrence.session.start))" }
}

/// Courses home (1a, 1b): loads courses, notes, grades and the timetable through the API and
/// applies the user's grouping, sorting and faculty filter (`CourseListQuery`).
@MainActor @Observable
public final class CoursesOverviewModel {
    public enum Mode: String, Sendable { case grid, timetable }
    public enum Grouping: String, CaseIterable, Sendable { case none, faculty }

    /// „Show“ toggles of the timetable sidebar; a session kind belongs to one of them.
    public enum KindGroup: String, CaseIterable, Sendable {
        case lectures, labs, seminars

        public var title: String {
            switch self {
            case .lectures: "Lectures"
            case .labs: "Labs and tutorials"
            case .seminars: "Seminars"
            }
        }

        public static func of(kind: String) -> KindGroup {
            switch kind.lowercased() {
            case "lab", "tutorial", "practical", "cvičení", "laboratoř", "praktikum": .labs
            case "seminar", "seminář": .seminars
            default: .lectures
            }
        }
    }

    public var mode: Mode
    public var grouping: Grouping = .none
    public var sort: CourseListQuery.SortKey = .name
    /// Selected faculty chip; nil = All courses.
    public var faculty: String?
    /// Week shown in the timetable (1-based).
    public private(set) var week: Int = 1
    public private(set) var currentWeek: Int?
    public private(set) var semester: Semester?
    public private(set) var semesters: [Semester] = []
    /// Session kinds hidden in the timetable.
    public var hiddenKinds: Set<KindGroup> = []
    public private(set) var cards: [CourseCardData] = []
    public private(set) var isLoaded = false

    /// Name of the group for courses without a faculty.
    public static let otherFaculty = "Other"

    private let env: AppEnvironment
    private var dueCounts: [CourseID: Int] = [:]
    private var openCounts: [CourseID: Int] = [:]
    private var notesByCourse: [CourseID: [NoteSummary]] = [:]
    private var weekBlocks: [TimetableBlock] = []

    public init(env: AppEnvironment, mode: Mode = .grid) {
        self.env = env
        self.mode = mode
    }

    public var clock: any Clock { env.clock }

    // MARK: Loading

    public func load() async {
        do {
            let semesters = try await env.courses.semesters()
            self.semesters = semesters
            let today = env.clock.today
            semester = semesters.first { $0.start <= today && today <= $0.end } ?? semesters.last
            currentWeek = semester.flatMap { env.clock.weekOfSemester($0) }
            if !isLoaded { week = currentWeek ?? 1 }

            let courses = try await env.courses.courses(query: nil)
            let upcoming = try await upcomingOccurrences()
            var cards: [CourseCardData] = []
            var due: [CourseID: Int] = [:]
            var open: [CourseID: Int] = [:]
            var notesByCourse: [CourseID: [NoteSummary]] = [:]
            for course in courses {
                let notes = try await env.notes.notes(course: course.id)
                notesByCourse[course.id] = notes
                let grade = try await env.grades.average(course: course.id)
                let tasks = try await env.tasks.tasks(course: course.id)
                due[course.id] = CourseListQuery.dueCounts(from: tasks)[course.id] ?? 0
                open[course.id] = tasks.filter { !$0.done && $0.kind == .task }.count
                let next = upcoming.first { $0.session.courseID == course.id }
                cards.append(CourseCardData(
                    course: course,
                    noteCount: notes.filter { !$0.isPlaceholder }.count,
                    grade: grade?.letter,
                    next: next.map { Self.nextLine($0, notes: notes) }))
            }
            self.cards = cards
            self.dueCounts = due
            self.openCounts = open
            self.notesByCourse = notesByCourse
            try await loadWeek()
            isLoaded = true
        } catch {
            // The catalog is in memory or on disk; a failed read leaves the last good state.
            isLoaded = true
        }
    }

    /// Keeps the screen in sync with the catalog (a course added, renamed or restyled elsewhere).
    public func observe() async {
        for await _ in env.courses.updates { await load() }
    }

    private func loadWeek() async throws {
        guard semester != nil else { weekBlocks = []; return }
        let byID = Dictionary(cards.map { ($0.id, $0.course) }, uniquingKeysWith: { a, _ in a })
        weekBlocks = try await env.courses.sessions(week: week)
            .filter { !$0.isCancelled }
            .compactMap { occurrence in
                guard let course = byID[occurrence.session.courseID] else { return nil }
                return TimetableBlock(occurrence: occurrence, code: course.code, style: course.style)
            }
    }

    /// Blocks of the shown week without the hidden kinds.
    public var blocks: [TimetableBlock] {
        weekBlocks.filter { !hiddenKinds.contains(KindGroup.of(kind: $0.occurrence.session.kind)) }
    }

    /// Classes of the shown week in a kind group (sidebar counts; hidden ones included).
    public func count(of group: KindGroup) -> Int {
        weekBlocks.filter { KindGroup.of(kind: $0.occurrence.session.kind) == group }.count
    }

    public func toggle(_ group: KindGroup) {
        if hiddenKinds.contains(group) { hiddenKinds.remove(group) } else { hiddenKinds.insert(group) }
    }

    /// Tab title for a class: its note („Lecture 9 — Membrane transport“), else „Lecture · Tue 29 Sep“.
    public func title(of occurrence: SessionOccurrence) -> String {
        if let note = notesByCourse[occurrence.session.courseID]?.first(where: { $0.date == occurrence.date }) {
            return note.title
        }
        let d = occurrence.date
        return "\(occurrence.session.kind) · \(CoursesFormat.weekday(d.weekday)) \(d.day) \(CoursesFormat.month(d.month))"
    }

    public func course(id: CourseID) -> Course? { cards.first { $0.id == id }?.course }

    /// The note of a class (same course, same date), if one exists.
    public func note(for occurrence: SessionOccurrence) -> NoteSummary? {
        notesByCourse[occurrence.session.courseID]?.first { $0.date == occurrence.date }
    }

    /// Course of a known note.
    public func courseID(ofNote id: NoteID) -> CourseID? {
        notesByCourse.first { $0.value.contains { $0.id == id } }?.key
    }

    public func notes(of course: CourseID) -> [NoteSummary] { notesByCourse[course] ?? [] }

    /// Open tasks of a course, with or without a date (hover card 3e).
    public func openTasks(of course: CourseID) -> Int { openCounts[course] ?? 0 }

    /// Monday–Friday range of a week („28 Sep – 2 Oct“).
    public func range(ofWeek week: Int) -> String {
        guard let semester else { return "" }
        let first = semester.start.startOfWeek.adding(days: (week - 1) * 7)
        let last = first.adding(days: 4)
        return first.month == last.month
            ? "\(first.day) – \(last.day) \(CoursesFormat.month(last.month))"
            : "\(first.day) \(CoursesFormat.month(first.month)) – \(last.day) \(CoursesFormat.month(last.month))"
    }

    /// Classes from now on in this week and the next, earliest first (overrides applied).
    private func upcomingOccurrences() async throws -> [SessionOccurrence] {
        guard let current = currentWeek, let semester else { return [] }
        let now = env.clock.localNow
        var result: [SessionOccurrence] = []
        for week in [current, current + 1] where week <= semester.weekCount {
            result += try await env.courses.sessions(week: week)
        }
        return result.filter { !$0.isCancelled && $0.start >= now }.sorted { $0.start < $1.start }
    }

    /// „Tue 10:00 · Lecture 9 · Membrane transport“: the note of that class names it, else its kind.
    static func nextLine(_ occurrence: SessionOccurrence, notes: [NoteSummary]) -> String {
        let when = "\(CoursesFormat.weekday(occurrence.date.weekday)) \(CoursesFormat.hour(occurrence.session.start))"
        let title = notes.first { $0.date == occurrence.date }?.title
            .replacingOccurrences(of: " — ", with: " · ")
        return "\(when) · \(title ?? occurrence.session.kind)"
    }

    // MARK: Grid

    /// Faculties present in the data, for the filter chips.
    public var faculties: [String] {
        Array(Set(cards.compactMap(\.course.faculty))).sorted()
    }

    public var visibleCards: [CourseCardData] {
        let query = CourseListQuery(sortBy: sort, faculties: faculty.map { [$0] } ?? [])
        let order = query.apply(to: cards.map(\.course),
                                context: .init(now: env.clock.localNow, dueCounts: dueCounts))
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return order.compactMap { byID[$0.id] }
    }

    /// Cards in groups; one untitled group when not grouping. Faculties alphabetically, „Other“ last.
    public var groups: [(title: String?, cards: [CourseCardData])] {
        let cards = visibleCards
        guard grouping == .faculty else { return [(nil, cards)] }
        let grouped = Dictionary(grouping: cards) { $0.course.faculty ?? Self.otherFaculty }
        let titles = grouped.keys.sorted { a, b in
            if a == Self.otherFaculty { return false }
            if b == Self.otherFaculty { return true }
            return a < b
        }
        return titles.map { ($0, grouped[$0] ?? []) }
    }

    /// „Fall 2026 · Week 5 of 15“.
    public var semesterLine: String {
        guard let semester else { return "" }
        guard let currentWeek else { return semester.name }
        return "\(semester.name) · Week \(currentWeek) of \(semester.weekCount)"
    }

    // MARK: Timetable

    public var weekDays: [LocalDate] {
        guard let semester else { return [] }
        let monday = semester.start.startOfWeek.adding(days: (week - 1) * 7)
        return (0..<5).map { monday.adding(days: $0) }
    }

    /// „28 Sep – 2 Oct · 11 sessions“.
    public var weekLine: String {
        guard semester != nil else { return "" }
        let count = blocks.count == 1 ? "1 session" : "\(blocks.count) sessions"
        return "\(range(ofWeek: week)) · \(count)"
    }

    public var canGoBack: Bool { week > 1 }
    public var canGoForward: Bool { week < (semester?.weekCount ?? 1) }

    public func showWeek(_ week: Int) async {
        let last = semester?.weekCount ?? 1
        self.week = min(max(week, 1), last)
        try? await loadWeek()
    }

    public func showThisWeek() async {
        await showWeek(currentWeek ?? 1)
    }
}

/// English date labels of the mockups (the app UI is English, like the mockups).
enum CoursesFormat {
    static func weekday(_ day: Weekday) -> String { String(day.fullName.prefix(3)).capitalized }

    static func month(_ month: Int) -> String {
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][max(0, min(11, month - 1))]
    }

    /// „10:00“, „9:00“ (no leading zero, like the mockup).
    static func hour(_ time: LocalTime) -> String { String(format: "%d:%02d", time.hour, time.minute) }
}
