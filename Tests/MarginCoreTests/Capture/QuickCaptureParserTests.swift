import Foundation
import Testing
@testable import MarginCore

private struct Case {
    let input: String
    let course: CourseID?
    let due: LocalDate?
    let tags: [String]
    let kind: InboxKind

    init(_ input: String, _ course: CourseID? = nil, _ due: LocalDate? = nil, tags: [String] = [], _ kind: InboxKind = .task) {
        self.input = input; self.course = course; self.due = due; self.tags = tags; self.kind = kind
    }

    init(_ input: String, _ kind: InboxKind) { self.init(input, nil, nil, tags: [], kind) }
    init(_ input: String, _ course: CourseID?, _ kind: InboxKind) { self.init(input, course, nil, tags: [], kind) }
    init(_ input: String, tags: [String], _ kind: InboxKind) { self.init(input, nil, nil, tags: tags, kind) }
    init(_ input: String, _ course: CourseID?, tags: [String], _ kind: InboxKind) { self.init(input, course, nil, tags: tags, kind) }
}

private func d(_ m: Int, _ day: Int, _ y: Int = 2026) -> LocalDate { LocalDate.literal(y, m, day) }

@Suite struct QuickCaptureParserTests {
    static var inputs: [String] { table.map(\.input) }
    // FixedClock: Monday 2026-09-28 13:24.
    static let parser = QuickCaptureParser(courses: Fixtures.week5.courses, clock: FixedClock(), notes: Fixtures.week5.notes)

    /// Exactly 60 sentences: (course, due, tags, kind).
    private static let table: [Case] = [
        Case("Email Dr. Okafor about lab partner tomorrow #bio", "bio", d(9, 29)),
        Case("Read ch. 7 for orgo by Fri", "chem", d(10, 2)),
        Case("Midterm review bio @2026-10-01", "bio", d(10, 1)),
        Case("note: membrane transport idea", .note),
        Case("https://en.wikipedia.org/wiki/Cell_membrane", .link),
        Case("Finish problem set 4 for linear algebra by friday 5pm", "math", d(10, 2)),
        Case("Buy printer paper"),
        Case("Lab report TLC due tomorrow chem", "chem", d(9, 29)),
        Case("Read chapter 8 hist", "hist"),
        Case("Essay proposal econ next week", "econ", d(10, 5)),
        Case("Call mom tonight", nil, d(9, 28)),
        Case("Submit response paper phil on thursday", "phil", d(10, 1)),
        Case("Quiz prep macro in 3 days", "econ", d(10, 1)),
        Case("idea: compare mitochondria and chloroplasts #bio #idea", "bio", tags: ["idea"], .note),
        Case("Review slides for lecture 8 bio", "bio", .note),
        Case("Read paper #reading #bio201 by Oct 5", "bio", d(10, 5), tags: ["reading"]),
        Case("Print syllabus HIST 210 tomorrow", "hist", d(9, 29)),
        Case("Study for MATH 221 midterm @before-midterm", "math", d(10, 13)),
        Case("Email Prof. Lindqvist about lab #urgent", "chem", tags: ["urgent"]),
        Case("Pick up laptop charger friday", nil, d(10, 2)),
        Case("Renew library books on oct 12", nil, d(10, 12)),
        Case("Finish lab notebook 5 oct", nil, d(10, 5)),
        Case("Check www.khanacademy.org for orgo", "chem", .link),
        Case("Whiteboard.png bio", "bio", .image),
        Case("task: buy blue book for econ exam", "econ"),
        Case("link: https://arxiv.org/abs/1706.03762 #ml", tags: ["ml"], .link),
        Case("Do practice exam in 2 weeks math", "math", d(10, 12)),
        Case("Meet study group sunday", nil, d(10, 4)),
        Case("Someday learn Swift"),
        Case("Revise notes for lecture bio", "bio", .note),
        Case("Read Cell Biology chapter 6 by Wed", "bio", d(9, 30)),
        Case("Buy groceries @tomorrow", nil, d(9, 29)),
        Case("Homework due @fri #math", "math", d(10, 2)),
        Case("Write essay on Modern Europe @2026-11-02", "hist", d(11, 2)),
        Case("Ask Dr. Haddad about determinants", "math"),
        Case("Lunch with Sam at 12:30 tomorrow", nil, d(9, 29)),
        Case("Finish reading The Prince by Oct 15 hist", "hist", d(10, 15)),
        Case("Mock exam 4th of november math", "math", d(11, 4)),
        Case("Turn in TLC report today chem", "chem", d(9, 28)),
        Case("Prep seminar phil next thursday", "phil", d(10, 1)),
        Case("Group project meeting this friday econ", "econ", d(10, 2)),
        Case("Send thanks to Prof. Brennan", "hist"),
        Case("note: Okafor said midterm covers lectures 5-8 #bio", "bio", .note),
        Case("Sort out student loan forms"),
        Case("Apply for internship by dec 1", nil, d(12, 1)),
        Case("Do laundry #home", tags: ["home"]),
        Case("Reading response on Philosophy of Mind due tue", "phil", d(9, 29)),
        Case("Add to lecture 9 the enzyme kinetics diagram #bio", "bio", .note),
        Case("Chem lab safety quiz Thursday", "chem", d(10, 1)),
        Case("Bio lecture 10 notes to review", "bio"),
        Case("idea: what if enzymes are like keys? #bio", "bio", .note),
        Case("Watch https://youtu.be/dQw4w9WgXcQ before econ quiz", "econ", .link),
        Case("Finish ECON 102 problem set by 2026-10-06", "econ", d(10, 6)),
        Case("Buy milk, eggs and bread tomorrow", nil, d(9, 29)),
        Case("Email TA @today #econ", "econ", d(9, 28)),
        Case("Return call to advisor next week", nil, d(10, 5)),
        Case("Prepare talk for orgo tutorial friday at 3pm", "chem", d(10, 2)),
        Case("Photo of whiteboard IMG_2041.heic #hist", "hist", .image),
        Case("Sketch macro model by tues", "econ", d(9, 29)),
        Case("Finish chem problem set @fri 9am", "chem", d(10, 2)),
    ]

    @Test func sixtySentences() {
        #expect(Self.table.count == 60)
        var failures: [String] = []
        for c in Self.table {
            let got = Self.parser.parse(c.input).draft
            if got.course != c.course || got.due != c.due || got.tags != c.tags || got.kind != c.kind {
                failures.append("\"\(c.input)\" expected (\(c.course ?? "-"), \(c.due?.iso ?? "-"), \(c.tags), \(c.kind)) "
                    + "got (\(got.course ?? "-"), \(got.due?.iso ?? "-"), \(got.tags), \(got.kind))")
            }
        }
        let correct = Self.table.count - failures.count
        print("QuickCaptureParser: \(correct)/\(Self.table.count) correct")
        for f in failures { print("  FAIL \(f)") }
        #expect(correct >= 57, "at least 95 % of 60 sentences (57) must be parsed correctly")
    }

    @Test func spansCoverChips() throws {
        let text = "Finish problem set 4 for linear algebra by friday 5pm #hw"
        let r = Self.parser.parse(text)
        func sub(_ kind: CaptureSpanKind) throws -> String {
            let span = try #require(r.spans.first { $0.kind == kind })
            return String(text[try #require(span.range(in: text))])
        }
        #expect(try sub(.course) == "linear algebra")
        #expect(try sub(.date) == "by friday 5pm")
        #expect(try sub(.tag) == "#hw")
        #expect(r.dueTime == LocalTime.literal(17))
        #expect(r.draft.text == "Finish problem set 4 for linear algebra by friday 5pm")
        #expect(r.draft.tags == ["hw"])
        // Spans are ordered and never overlap.
        for (a, b) in zip(r.spans, r.spans.dropFirst()) { #expect(a.range.upperBound <= b.range.lowerBound) }
    }

    @Test func explicitMarkupIsStrippedFromText() {
        let r = Self.parser.parse("note: Midterm review bio @2026-10-01 #exam")
        #expect(r.draft.text == "Midterm review bio")
        #expect(r.draft.kind == .note)
        #expect(r.draft.tags == ["exam"])
        #expect(r.spans.map(\.kind).contains(.kindPrefix))
    }

    @Test func attachToLectureNote() {
        let numbered = Self.parser.parse("Add to lecture 9 the enzyme diagram #bio")
        #expect(numbered.draft.attachTo == "bio/lecture-9")
        #expect(numbered.lectureHint == CaptureLectureHint(number: 9))
        #expect(numbered.spans.contains { $0.kind == .attachment })
        let bare = Self.parser.parse("Revise notes for lecture bio")
        #expect(bare.lectureHint == CaptureLectureHint(number: nil))
        // Latest lecture up to today (Mon 28 Sep): Lecture 8 (24 Sep), not Lecture 9 (29 Sep).
        #expect(bare.draft.attachTo == "bio/lecture-8")
        // Without a course or notes there is nothing to resolve, but the hint stays.
        let noNotes = QuickCaptureParser(courses: Fixtures.week5.courses, clock: FixedClock())
        #expect(noNotes.parse("Add to lecture 9 the diagram #bio").draft.attachTo == nil)
        #expect(Self.parser.parse("Add to lecture 9 the diagram").draft.attachTo == nil)
    }

    @Test func courseAliasesAndAmbiguity() {
        #expect(Self.parser.parse("read BIO 201 slides").draft.course == "bio")
        #expect(Self.parser.parse("read bio201 slides").draft.course == "bio")
        #expect(Self.parser.parse("CHEMISTRY quiz").draft.course == "chem")
        #expect(Self.parser.parse("ask about linalg").draft.course == "math")
        // Hashtag beats a plain word; higher-priority alias beats a professor surname.
        #expect(Self.parser.parse("orgo homework with Okafor #math").draft.course == "math")
        #expect(Self.parser.parse("orgo homework with Okafor").draft.course == "chem")
        // Explicit alias table.
        let custom = QuickCaptureParser(courses: Fixtures.week5.courses, clock: FixedClock(), extraAliases: ["hist": ["euro"]])
        #expect(custom.parse("read euro ch 2").draft.course == "hist")
        // An alias that fits two courses is dropped.
        let twins = Fixtures.week5.courses.filter { $0.id == "bio" || $0.id == "chem" }
            .map { c -> Course in var c = c; c.professor = "Dr. Same"; return c }
        #expect(QuickCaptureParser(courses: twins, clock: FixedClock()).parse("ask Same").draft.course == nil)
    }

    @Test func dateSemantics() {
        func due(_ s: String) -> LocalDate? { Self.parser.parse(s).draft.due }
        #expect(due("x monday") == d(10, 5))            // strictly after today, like @Mon
        #expect(due("x day after tomorrow") == d(9, 30))
        #expect(due("x by oct 1") == d(10, 1))
        #expect(due("x sep 1") == d(9, 1, 2027))        // already past this year -> next year
        #expect(due("x sep 1 2028") == d(9, 1, 2028))
        #expect(due("x on feb 30") == nil)
        #expect(due("x in a week") == d(10, 5))
        #expect(due("x fri") == nil)                    // bare abbreviation is not a date
        #expect(due("x may") == nil)
        #expect(due("x @2026-02-30") == nil)
        #expect(due("x tomorrow, submit by friday") == d(10, 2)) // last natural date wins
        #expect(due("x tomorrow @2026-11-02") == d(11, 2))       // explicit token wins
        #expect(due("x @before-lecture #bio") == d(9, 28))       // next bio lecture Tue 29 Sep
    }

    @Test func degenerateInput() {
        for s in ["", "   ", "#", "@", "@@@", "note:", "# 4", "#bio", "\u{1F600} tomorrow \u{1F600}", "a@b.com"] {
            let r = Self.parser.parse(s)
            for span in r.spans { #expect(span.range(in: s) != nil) }
        }
        #expect(Self.parser.parse("#bio").draft.text == "#bio")
        #expect(Self.parser.parse("a@b.com").draft.due == nil)
        #expect(Self.parser.parse("problem #4").draft.tags.isEmpty)
    }

    @Test func fuzzNeverCrashes() {
        var rng = SplitMix64(seed: 0xC0FFEE)
        let pieces = ["tomorrow", "fri", "by", "@", "#", "bio", "orgo", "lecture", "to", "5pm", "at", "12:30", "oct", "5", "2026-10-01",
                      "note:", "https://x.io", "in", "3", "days", "next", "week", "\u{1F600}", " ", "-", ":", "of", "may", "\n"]
        for _ in 0..<2000 {
            var s = ""
            for _ in 0..<Int(rng.next() % 12) { s += pieces[Int(rng.next() % UInt64(pieces.count))] + (rng.next() % 3 == 0 ? "" : " ") }
            let r = Self.parser.parse(s)
            for span in r.spans { #expect(span.range(in: s) != nil) }
            for (a, b) in zip(r.spans, r.spans.dropFirst()) { #expect(a.range.upperBound <= b.range.lowerBound, "\(s.debugDescription) \(r.spans)") }
        }
    }
}

extension PerfSuites {
@Suite struct QuickCaptureParserPerfTests {
    /// Budget is 5 ms per parse (M-capture); the average over 60 sentences x 20 rounds is measured
    /// `perfRuns` times after a warm-up and the median is asserted.
    @Test func latencyUnderBudget() {
        let inputs = QuickCaptureParserTests.inputs
        let rounds = 20
        var sink = 0
        let clock = ContinuousClock()
        let samples = perfSamples { () -> Double in
            let elapsed = clock.measure {
                for _ in 0..<rounds { for s in inputs { sink &+= QuickCaptureParserTests.parser.parse(s).spans.count } }
            }
            return perfMs(elapsed / (rounds * inputs.count))
        }
        let median = perfMedian(samples)
        print("QuickCaptureParser: median \(String(format: "%.3f", median)) ms per parse over \(perfRuns) runs [\(samples.map { String(format: "%.3f", $0) }.joined(separator: "/"))] (sink \(sink))")
        #expect(median < 5)
    }
}
}
