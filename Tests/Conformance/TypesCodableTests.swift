import Foundation
import Testing
@testable import MarginCore

private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    let back = try JSONDecoder().decode(T.self, from: data)
    #expect(back == value)
}

private let d = LocalDate.literal(2026, 10, 1)
private let t = LocalTime.literal(10, 0)

@Suite struct TypesCodableTests {
    @Test func calendarValues() throws {
        try roundTrip(d)
        try roundTrip(t)
        try roundTrip(LocalDateTime(date: d, time: t))
        try roundTrip(Weekday.friday)
        #expect(LocalDate(iso: "2026-02-29") == nil)
        #expect(LocalDate.literal(2026, 9, 28).weekday == .monday)
        #expect(LocalDate.literal(2026, 9, 28).adding(days: 3) == d)
        #expect(String(data: try JSONEncoder().encode(d), encoding: .utf8) == "\"2026-10-01\"")
    }

    @Test func errorsEncodeStableShape() throws {
        let all: [MarginError] = [.io("a"), .conflict("b"), .notFound("c"), .invalid("d"),
                                  .readOnly("e"), .forbidden("f"), .rateLimited("g")]
        for e in all { try roundTrip(e) }
        let json = String(data: try JSONEncoder().encode(MarginError.notFound("x")), encoding: .utf8)
        #expect(json?.contains("\"code\":\"notFound\"") == true)
        let bad = Data(#"{"code":"nope","message":"m"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(MarginError.self, from: bad) }
    }

    @Test func modelTypes() throws {
        let semester = Semester(id: "fall-2026", name: "Fall 2026",
                                start: .literal(2026, 8, 31), end: .literal(2026, 12, 13), breakWeeks: [9])
        try roundTrip(semester)
        #expect(semester.week(of: .literal(2026, 9, 28)) == 5)
        #expect(semester.week(of: .literal(2026, 8, 30)) == nil)
        #expect(semester.weekCount == 15)

        let session = Session(courseID: "bio", day: .tuesday, start: t, lengthHours: 1.5, kind: "Lecture", room: "Sci 204")
        #expect(session.id == "bio-tue-1000")
        #expect(session.lengthMinutes == 90)
        #expect(session.end == LocalTime.literal(11, 30))
        try roundTrip(session)
        try roundTrip(SessionOverride(sessionID: session.id, courseID: "bio", originalDate: .literal(2026, 9, 29),
                                      cancelled: false, newStart: LocalDateTime(date: d, time: t), newRoom: "X", note: "n"))
        let exam = Exam(courseID: "bio", title: "Midterm", date: d, weightPercent: 25)
        try roundTrip(exam)
        let style = CourseStyle(icon: "eco", color: "bio", background: "#D8EFD9", foreground: "#2F7D3E", dot: "#6FBF7A")
        try roundTrip(style)
        try roundTrip(Course(id: "bio", semester: semester.id, name: "Cell Biology", code: "BIO 201",
                             professor: "Dr. Okafor", room: "Sci 204", faculty: "Sciences", credits: 5,
                             style: style, sessions: [session], exams: [exam],
                             grading: [GradingPart(label: "Midterm", weightPercent: 25)]))
    }

    @Test func noteTaskGradeInboxGraphTypes() throws {
        let summary = NoteSummary(id: "bio/l8", courseID: "bio", title: "Lecture 8", kind: .lecture, date: d,
                                  snippet: "s", wordCount: 412, openTasks: 2, totalTasks: 2, imageCount: 0,
                                  isPlaceholder: false, modified: LocalDateTime(date: d, time: t))
        try roundTrip(summary)
        try roundTrip(Note(summary: summary, text: "# Lecture 8", version: "3"))

        let loc = TaskLocation(noteID: "bio/l8", line: 12, courseID: "bio")
        try roundTrip(loc)
        for label in [DueLabel.overdue(days: 2), .today, .tomorrow, .weekday(.wednesday), .date(d)] { try roundTrip(label) }
        try roundTrip(TaskItem(id: "t1", text: "Read", due: d, label: .today, done: true, kind: .exam, source: loc))

        let today = LocalDate.literal(2026, 9, 28)
        #expect(DueLabel.make(due: today.adding(days: -3), today: today) == .overdue(days: 3))
        #expect(DueLabel.make(due: today, today: today) == .today)
        #expect(DueLabel.make(due: today.adding(days: 1), today: today) == .tomorrow)
        #expect(DueLabel.make(due: today.adding(days: 2), today: today) == .weekday(.wednesday))
        #expect(DueLabel.make(due: today.adding(days: 7), today: today) == .date(today.adding(days: 7)))

        let grade = Grade(id: "g1", courseID: "bio", item: "PS1", group: "Problem sets", weightPercent: 5,
                          score: 19, max: 20, date: d)
        try roundTrip(grade)
        #expect(grade.percent == 95)
        #expect(Grade(id: "g2", courseID: "bio", item: "Final").percent == nil)
        try roundTrip(GradeSummary(courseID: "bio", letter: "A−", percent: 91))

        for src in InboxSource.allCases {
            try roundTrip(InboxItem(id: "i", text: "x", kind: .link, source: src,
                                    captured: LocalDateTime(date: d, time: t)))
        }
        try roundTrip(CaptureDraft(text: "x", course: "bio", due: d, tags: ["a"], kind: .note, attachTo: "bio/l8"))

        let graph = Graph(nodes: [GraphNode(id: "bio", label: "Cell Biology", kind: .course, courseID: "bio", x: 420, y: 330),
                                  GraphNode(id: "b1", label: "L8", kind: .note, courseID: "bio", x: 350, y: 225)],
                          edges: [GraphEdge(source: "bio", target: "b1")])
        try roundTrip(graph)
        #expect(graph.edges[0].id == "bio--b1")
    }
}
