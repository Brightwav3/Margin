/// In-memory sample data for previews, the gallery and the `Fixture…` service implementations.
///
/// `Fixtures.week5` is transcribed 1:1 from `docs/design/mockups/Margin.dc.html` (and
/// `Margin-Screens.dc.html` for grades): Monday 28 Sep 2026, week 5 of Fall 2026, at 13:24
/// (see `FixedClock`). Values the mockup only shows as relative text ("Tomorrow", "Wed") are
/// resolved against that date. Values the mockup does not contain (line numbers, ids, capture
/// times) are invented and marked in the source.
public struct FixtureWorld: Sendable, Hashable {
    public var semester: Semester
    public var courses: [Course]
    /// Due items of the week (tasks and the exam), in mockup order.
    public var dueItems: [TaskItem]
    /// All notes: the Bio gallery first, then the other Bio notes, then one recent note per course.
    public var notes: [NoteSummary]
    public var inbox: [InboxItem]
    /// Graded items (Cell Biology only, as in the mockup).
    public var grades: [Grade]
    public var gradeSummaries: [GradeSummary]
    public var graph: Graph

    /// Weekly sessions of all courses, ordered by day then start.
    public var sessions: [Session] {
        courses.flatMap(\.sessions).sorted { ($0.day, $0.start) < ($1.day, $1.start) }
    }

    /// Exams of all courses, ordered by date.
    public var exams: [Exam] {
        courses.flatMap(\.exams).sorted { $0.date < $1.date }
    }

    /// Bio course notes shown as gallery cards (newest first, the upcoming one leading).
    public var bioGallery: [NoteSummary] { Array(notes.prefix(6)) }

    public func course(_ id: CourseID) -> Course? { courses.first { $0.id == id } }

    public init(
        semester: Semester, courses: [Course], dueItems: [TaskItem], notes: [NoteSummary] = [],
        inbox: [InboxItem] = [], grades: [Grade] = [], gradeSummaries: [GradeSummary] = [],
        graph: Graph = Graph()
    ) {
        self.semester = semester; self.courses = courses; self.dueItems = dueItems; self.notes = notes
        self.inbox = inbox; self.grades = grades; self.gradeSummaries = gradeSummaries; self.graph = graph
    }
}

public enum Fixtures {
    /// The fixture clock day: Monday 28 Sep 2026.
    public static let today = FixedClock.defaultLocal.date

    /// Week 5 of Fall 2026, as designed in the mockups.
    public static let week5 = FixtureWorld(
        semester: fall2026,
        courses: courses,
        dueItems: dueItems,
        notes: notes,
        inbox: inbox,
        grades: grades,
        gradeSummaries: gradeSummaries,
        graph: graph
    )

    /// Fall 2026: week 1 starts Mon 31 Aug so that 28 Sep is week 5. The end (Sun 13 Dec) follows
    /// the final exam on 11 Dec shown in the Grades mockup. Both are decisions, not mockup data.
    static let fall2026 = Semester(
        id: "fall-2026", name: "Fall 2026",
        start: .literal(2026, 8, 31), end: .literal(2026, 12, 13))

    private static func style(_ icon: String, _ color: String, _ bg: String, _ fg: String, _ dot: String) -> CourseStyle {
        CourseStyle(icon: icon, color: color, background: bg, foreground: fg, dot: dot)
    }

    private static func sessions(_ id: CourseID, _ rows: [(Weekday, Int, Double, String, String?)]) -> [Session] {
        rows.map { Session(courseID: id, day: $0.0, start: .literal($0.1), lengthHours: $0.2, kind: $0.3, room: $0.4) }
    }

    // Sessions: `SES` in the mockup, `[dayIndex, course, startHour, hours, kind]`. The mockup shows a
    // room only for each course's next session; other sessions have no room.
    static let courses: [Course] = [
        Course(
            id: "bio", semester: "fall-2026", name: "Cell Biology", code: "BIO 201",
            professor: "Dr. Okafor", room: "Sci 204", faculty: "Sciences", credits: 5,
            style: style("eco", "bio", "#D8EFD9", "#2F7D3E", "#6FBF7A"),
            sessions: sessions("bio", [(.tuesday, 10, 1.5, "Lecture", "Sci 204"), (.thursday, 10, 1.5, "Lecture", "Sci 204")]),
            exams: [Exam(courseID: "bio", title: "Midterm", date: .literal(2026, 10, 1), weightPercent: 25)],
            grading: [GradingPart(label: "Problem sets", weightPercent: 20),
                      GradingPart(label: "Lab reports", weightPercent: 25),
                      GradingPart(label: "Midterm", weightPercent: 25),
                      GradingPart(label: "Final exam", weightPercent: 30)]),
        Course(
            id: "chem", semester: "fall-2026", name: "Organic Chemistry", code: "CHEM 230",
            professor: "Prof. Lindqvist", room: "Lab C",
            style: style("science", "chem", "#D9E7DC", "#2F5D3A", "#7FA88A"),
            sessions: sessions("chem", [(.monday, 14, 3, "Lab", "Lab C"), (.friday, 13, 1.5, "Lecture", nil)])),
        Course(
            id: "math", semester: "fall-2026", name: "Linear Algebra", code: "MATH 221",
            professor: "Dr. Haddad", room: "Math 101",
            style: style("change_history", "math", "#D6E2FA", "#274FA8", "#6E97EC"),
            sessions: sessions("math", [(.monday, 11, 1.5, "Lecture", nil), (.wednesday, 11, 1.5, "Lecture", "Math 101")]),
            exams: [Exam(courseID: "math", title: "Midterm", date: .literal(2026, 10, 14), weightPercent: 30)]),
        Course(
            id: "hist", semester: "fall-2026", name: "Modern Europe", code: "HIST 210",
            professor: "Prof. Brennan", room: "Arts 3.12",
            style: style("account_balance", "hist", "#FBE8C4", "#8F5D0E", "#E8B85C"),
            sessions: sessions("hist", [(.wednesday, 13, 2, "Seminar", "Arts 3.12"), (.friday, 11, 1, "Lecture", nil)])),
        Course(
            id: "econ", semester: "fall-2026", name: "Macroeconomics", code: "ECON 102",
            professor: "Dr. Silva", room: "Hall B",
            style: style("trending_up", "econ", "#E5DEF8", "#5B41B0", "#9A86DE"),
            sessions: sessions("econ", [(.tuesday, 15, 1.5, "Lecture", "Hall B"), (.friday, 9, 1, "Tutorial", nil)]),
            exams: [Exam(courseID: "econ", title: "Quiz 3", date: .literal(2026, 10, 6), weightPercent: 5)]),
        Course(
            id: "phil", semester: "fall-2026", name: "Philosophy of Mind", code: "PHIL 240",
            professor: "Dr. Moreau", room: "Arts 1.04",
            style: style("psychology", "phil", "#FADAD6", "#B3372B", "#EC8A80"),
            sessions: sessions("phil", [(.thursday, 16, 1.5, "Seminar", "Arts 1.04")])),
    ]

    // `DUE` in the mockup. Day labels resolve against Mon 28 Sep: Today, Tomorrow, Wed 30, Thu 1 Oct,
    // Fri 2 Oct. Note ids and line numbers are invented (the mockup has no source locations).
    private static func due(_ n: Int, _ course: CourseID, _ text: String, _ date: LocalDate,
                            done: Bool = false, kind: TaskKind = .task) -> TaskItem {
        TaskItem(
            id: "task-\(course)-\(text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.replacingOccurrences(of: " ", with: "-"))",
            text: text, due: date, label: DueLabel.make(due: date, today: today), done: done, kind: kind,
            source: TaskLocation(noteID: "\(course)/assignments", line: n, courseID: course))
    }

    static let dueItems: [TaskItem] = [
        due(1, "math", "Problem set 4", .literal(2026, 9, 28)),
        due(1, "chem", "Lab report: TLC", .literal(2026, 9, 29)),
        due(1, "bio", "Read chapter 6", .literal(2026, 9, 30), done: true),
        due(2, "bio", "Midterm", .literal(2026, 10, 1), kind: .exam),
        due(2, "hist", "Essay proposal", .literal(2026, 10, 2)),
        due(1, "phil", "Response paper", .literal(2026, 10, 2)),
    ]
}
