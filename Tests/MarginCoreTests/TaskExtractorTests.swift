import Testing
@testable import MarginCore

@Suite struct TaskExtractorTests {
    // FixedClock default: Monday 2026-09-28.
    static let clock = FixedClock()
    static let context = CourseEventContext(
        exams: [
            Exam(courseID: "bio", title: "Midterm", date: LocalDate.literal(2026, 10, 15), weightPercent: 25),
            Exam(courseID: "bio", title: "Final Exam", date: LocalDate.literal(2026, 12, 10), weightPercent: 50),
            Exam(courseID: "bio", title: "Quiz", date: LocalDate.literal(2026, 10, 2), weightPercent: 5),
            Exam(courseID: "bio", title: "Old midterm", date: LocalDate.literal(2026, 9, 1), weightPercent: 5),
        ],
        sessions: [
            Session(courseID: "bio", day: .tuesday, start: LocalTime.literal(10), lengthHours: 1.5, kind: "Lecture"),
            Session(courseID: "bio", day: .thursday, start: LocalTime.literal(9), lengthHours: 2, kind: "Lab"),
        ])

    static func d(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate.literal(y, m, d) }

    // 40 inputs -> expected due date (nil = no due date).
    static let table: [(String, LocalDate?)] = [
        // ISO
        ("- [ ] a @2026-10-02", d(2026, 10, 2)),
        ("- [x] a @2026-09-30", d(2026, 9, 30)),
        ("- [ ] a @2026-02-30", nil),
        ("- [ ] a @2026-13-01", nil),
        ("- [ ] a @2024-02-29", d(2024, 2, 29)),
        ("- [ ] a @2026-10-02.", d(2026, 10, 2)),
        // weekdays, today is Monday 2026-09-28
        ("- [ ] a @Mon", d(2026, 10, 5)),
        ("- [ ] a @monday", d(2026, 10, 5)),
        ("- [ ] a @Tue", d(2026, 9, 29)),
        ("- [ ] a @tuesday", d(2026, 9, 29)),
        ("- [ ] a @Wed", d(2026, 9, 30)),
        ("- [ ] a @Thu", d(2026, 10, 1)),
        ("- [ ] a @Fri", d(2026, 10, 2)),
        ("- [ ] a @Sat", d(2026, 10, 3)),
        ("- [ ] a @Sun", d(2026, 10, 4)),
        ("- [ ] a @SUNDAY", d(2026, 10, 4)),
        ("- [ ] a @Tues", nil),
        // space after @ (spec example)
        ("- [ ] Ask about the osmosis question in office hours @ Tue", d(2026, 9, 29)),
        ("- [ ] a @  Fri", d(2026, 10, 2)),
        ("- [ ] a @\tfriday", d(2026, 10, 2)),
        ("- [ ] a @ 2026-10-02", d(2026, 10, 2)),
        // relative
        ("- [ ] a @today", d(2026, 9, 28)),
        ("- [ ] a @Today", d(2026, 9, 28)),
        ("- [ ] a @tomorrow", d(2026, 9, 29)),
        ("- [ ] a @next-week", d(2026, 10, 5)),
        ("- [ ] a @ next-week", d(2026, 10, 5)),
        ("- [ ] a @next", nil),
        // course events
        ("- [ ] Redraw the bilayer diagram from memory @before-midterm", d(2026, 10, 14)),
        ("- [ ] a @before-exam", d(2026, 10, 1)),
        ("- [ ] a @before-lecture", d(2026, 9, 28)),
        ("- [ ] a @ before-midterm", d(2026, 10, 14)),
        // no due
        ("- [ ] plain task", nil),
        ("- [ ] mail me at x@Tue.com", nil),
        ("- [ ] ping @john about it", nil),
        ("- [ ] a @", nil),
        // several candidates: the last parsable wins
        ("- [ ] a @Tue @Fri", d(2026, 10, 2)),
        ("- [ ] a @john @2026-10-02", d(2026, 10, 2)),
        // with id suffix and in the middle
        ("- [ ] a @Fri ^t-4f2a", d(2026, 10, 2)),
        ("- [ ] a @Fri and more text", d(2026, 10, 2)),
        ("* [ ] star marker @tomorrow", d(2026, 9, 29)),
    ]

    @Test func dueTable() {
        #expect(Self.table.count == 40)
        let extractor = TaskExtractor(clock: Self.clock, context: Self.context)
        for (input, expected) in Self.table {
            let tasks = extractor.extract(from: input)
            #expect(tasks.count == 1, "\(input)")
            #expect(tasks.first?.due == expected, "\(input): got \(String(describing: tasks.first?.due))")
        }
    }

    @Test func mondayWeekdayIsNextMonday() {
        let sunday = FixedClock(local: LocalDateTime(date: Self.d(2026, 10, 4), time: LocalTime.literal(9)))
        let r = DueResolver(clock: sunday)
        #expect(r.resolve(.weekday(.sunday)) == Self.d(2026, 10, 11))
        #expect(r.resolve(.weekday(.monday)) == Self.d(2026, 10, 5))
        #expect(r.resolve(.nextWeek) == Self.d(2026, 10, 5))
    }

    @Test func courseEventsWithoutContextStayUnresolved() {
        let t = TaskExtractor(clock: Self.clock).extract(from: "- [ ] a @before-midterm")
        #expect(t[0].dueToken == .beforeMidterm)
        #expect(t[0].due == nil)
        #expect(t[0].text == "a")
    }

    @Test func textAndBlockIDParsing() {
        let extractor = TaskExtractor(clock: Self.clock)
        let t = extractor.extract(from: "- [ ] Read chapter 6 @ Tue ^t-4f2a\n- [ ] ^t-lone\n- [ ] no id ^\n")
        #expect(t[0].text == "Read chapter 6")
        #expect(t[0].blockID == "t-4f2a")
        #expect(t[0].rawText == "Read chapter 6 @ Tue ^t-4f2a")
        #expect(t[1].blockID == nil)
        #expect(t[1].text == "^t-lone")
        #expect(t[2].blockID == nil)
    }

    @Test func dueTokenInMiddleIsRemovedCleanly() {
        let t = TaskExtractor(clock: Self.clock).extract(from: "- [ ] Do @Fri the thing")
        #expect(t[0].text == "Do the thing")
    }

    @Test func nesting() {
        let text = """
        - [ ] parent
            - [ ] child
                - [x] grandchild
            - [ ] child two
        - [ ] second root

        Paragraph

          - [ ] new list
        """
        let t = TaskExtractor(clock: Self.clock).extract(from: text)
        #expect(t.map(\.depth) == [0, 1, 2, 1, 0, 0])
        #expect(t.map(\.parentLine) == [nil, 1, 2, 1, nil, nil])
        #expect(t[2].done)
    }

    @Test func tabIndentedNesting() {
        let t = TaskExtractor(clock: Self.clock).extract(from: "- [ ] a\n\t- [ ] b\n")
        #expect(t.map(\.depth) == [0, 1])
    }

    @Test func codeBlockTaskIsIgnoredByExtractor() {
        let t = TaskExtractor(clock: Self.clock).extract(from: "```\n- [ ] no @Tue\n```\n")
        #expect(t.isEmpty)
    }

    @Test func mapsToTaskItem() {
        let extractor = TaskExtractor(clock: Self.clock)
        let t = extractor.extract(from: "intro\n- [x] Do it @tomorrow ^t-9\n- [ ] no id")
        let item = extractor.taskItem(t[0], noteID: "bio/w5", courseID: "bio")
        #expect(item.id == "t-9")
        #expect(item.done)
        #expect(item.due == Self.d(2026, 9, 29))
        #expect(item.label == .tomorrow)
        #expect(item.source == TaskLocation(noteID: "bio/w5", line: 2, courseID: "bio"))
        #expect(extractor.taskItem(t[1], noteID: "bio/w5").id == "bio/w5#L3")
    }
}
