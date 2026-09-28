import Testing
@testable import MarginCore

private func roundTrip(_ text: String) -> Bool {
    let (fm, body) = Frontmatter.parse(text)
    let out = (fm?.render() ?? "") + body
    return Array(out.utf8) == Array(text.utf8)
}

private let specNote = """
---
date: 2026-09-24
class: "[[Cell Biology]]"
type: lecture          # lecture | lab | seminar | tutorial | study | note
session: 2026-09-24T10:00   # link to a timetable slot
tags:
  - membranes
  - midterm
due: 2026-10-01        # optional
weight: 25%            # optional
custom: keep me
---
# Body

Text
"""

@Suite("Frontmatter") struct FrontmatterTests {
    @Test func specNoteTypedAccessors() throws {
        let (fm, body) = Frontmatter.parse(specNote)
        let f = try #require(fm)
        #expect(body == "# Body\n\nText")
        #expect(f.date == LocalDate(year: 2026, month: 9, day: 24))
        #expect(f.className == "Cell Biology")
        #expect(f.kind == .lecture)
        #expect(f.session == LocalDateTime(iso: "2026-09-24T10:00"))
        #expect(f.tags == ["membranes", "midterm"])
        #expect(f.due == LocalDate(year: 2026, month: 10, day: 1))
        #expect(f.weight == 25)
        #expect(f.string(for: "custom") == "keep me")
        #expect(f.keys == ["date", "class", "type", "session", "tags", "due", "weight", "custom"])
        #expect(f.isValid)
        #expect(f.render() + body == specNote)
    }

    @Test func classTolerantParsing() throws {
        for (raw, expected) in [
            ("class: Cell Biology", "Cell Biology"),
            ("class: \"[[Cell Biology]]\"", "Cell Biology"),
            ("class: '[[Cell Biology]]'", "Cell Biology"),
            ("class: [[Cell Biology]]", "Cell Biology"),
            ("class: \"[[Cell Biology|Bio]]\"", "Cell Biology"),
        ] {
            let f = try #require(Frontmatter.parse("---\n\(raw)\n---\n").frontmatter)
            #expect(f.className == expected, "\(raw)")
        }
    }

    @Test func unknownKeysKeepOrderAndBytes() throws {
        let text = "---\nzeta: 1\nalpha:   [a,b ,c]   \n'quoted key': \"x\\ty\"\nmid: !!weird\n---\nbody"
        var f = try #require(Frontmatter.parse(text).frontmatter)
        f.set("date", .date(LocalDate(year: 2026, month: 1, day: 2)!))
        #expect(f.render() == "---\nzeta: 1\nalpha:   [a,b ,c]   \n'quoted key': \"x\\ty\"\nmid: !!weird\ndate: 2026-01-02\n---\n")
        #expect(f.keys == ["zeta", "alpha", "quoted key", "mid", "date"])
        #expect(f.value(for: "alpha") == ["a", "b", "c"])
        #expect(f.value(for: "quoted key") == "x\ty")
        #expect(f.value(for: "mid") == nil)
        #expect(f.validate().count == 1)
    }

    @Test func commentsSurviveUntouchedLines() throws {
        let text = "---\n# top comment\na: 1 # one\n\n# between\nb: two\n  # tail\n---\n"
        var f = try #require(Frontmatter.parse(text).frontmatter)
        f.set("b", "three")
        #expect(f.render() == "---\n# top comment\na: 1 # one\n\n# between\nb: three\n---\n")
        var g = try #require(Frontmatter.parse(text).frontmatter)
        g.set("a", 2)
        #expect(g.render() == "---\n# top comment\na: 2 # one\n\n# between\nb: two\n  # tail\n---\n")
    }

    @Test func editedScalarKeepsTrailingComment() throws {
        var f = try #require(Frontmatter.parse(specNote).frontmatter)
        f.kind = .lab
        #expect(f.render().contains("type: \"lab\"          # lecture") == false)
        #expect(f.render().contains("type: lab\n"))
        f.due = LocalDate(year: 2026, month: 11, day: 5)
        #expect(f.render().contains("due: 2026-11-05        # optional\n"))
    }

    @Test func crlfIsPreserved() throws {
        let text = "---\r\ndate: 2026-09-24\r\ntags:\r\n  - a\r\n---\r\nBody\r\nline\r\n"
        var f = try #require(Frontmatter.parse(text).frontmatter)
        #expect(roundTrip(text))
        #expect(f.tags == ["a"])
        f.set("id", "n-9c1e")
        f.set("date", .date(LocalDate(year: 2027, month: 1, day: 1)!))
        #expect(f.render() == "---\r\ndate: 2027-01-01\r\ntags:\r\n  - a\r\nid: n-9c1e\r\n---\r\n")
    }

    @Test func bomIsPreserved() throws {
        let text = "\u{FEFF}---\ndate: 2026-09-24\n---\nBody"
        let (fm, body) = Frontmatter.parse(text)
        let f = try #require(fm)
        #expect(f.hasBOM)
        #expect(f.date != nil)
        #expect(f.render() + body == text)
    }

    @Test func emptyFrontmatter() throws {
        let (fm, body) = Frontmatter.parse("---\n---\nBody")
        let f = try #require(fm)
        #expect(f.keys.isEmpty)
        #expect(body == "Body")
        #expect(f.render() == "---\n---\n")
        var g = f
        g.id = "n-1"
        #expect(g.render(body: body) == "---\nid: n-1\n---\nBody")
    }

    @Test func missingClosingFenceMeansNoFrontmatter() {
        let text = "---\ndate: 2026-09-24\nBody without closing"
        let (fm, body) = Frontmatter.parse(text)
        #expect(fm == nil)
        #expect(body == text)
    }

    @Test func noFrontmatterAtAll() {
        for text in ["", "# Title\n", "Hello\n---\na: b\n---\n", "\n---\na: b\n---\n", "--- \nx"] {
            let (fm, body) = Frontmatter.parse(text)
            #expect(fm == nil, "\(text.debugDescription)")
            #expect(body == text)
        }
    }

    @Test func fenceInsideBodyIsBody() throws {
        let text = "---\na: 1\n---\nIntro\n\n---\n\nb: 2\n---\n"
        let (fm, body) = Frontmatter.parse(text)
        let f = try #require(fm)
        #expect(f.keys == ["a"])
        #expect(body == "Intro\n\n---\n\nb: 2\n---\n")
    }

    @Test func closingFenceAtEndOfFileWithoutNewline() throws {
        let (fm, body) = Frontmatter.parse("---\na: 1\n---")
        #expect(try #require(fm).render() == "---\na: 1\n---")
        #expect(body == "")
    }

    @Test func courseFileWithFlowMapsInLists() throws {
        let text = """
        ---
        name: Cell Biology
        code: BIO 201
        credits: 5
        sessions:
          - {day: Tue, time: "10:00", length: 1.5, kind: Lecture, room: "Sci 204"}
          - {day: Thu, time: "10:00", length: 1.5, kind: Lecture, room: "Sci 204"}
        exams:
          - {title: Midterm, date: 2026-10-01, weight: 25%}
        grading:
          - {label: Problem sets, weight: 20%}
        ---
        """
        let f = try #require(Frontmatter.parse(text).frontmatter)
        #expect(f.isValid)
        #expect(f.number(for: "credits") == 5)
        let sessions = try #require(f.list(for: "sessions"))
        #expect(sessions.count == 2)
        #expect(sessions[0]["day"] == "Tue")
        #expect(sessions[0]["time"] == "10:00")
        #expect(sessions[0]["length"] == 1.5)
        #expect(sessions[1]["room"] == "Sci 204")
        let exams = try #require(f.list(for: "exams"))
        #expect(exams[0]["date"] == .date(LocalDate(year: 2026, month: 10, day: 1)!))
        #expect(exams[0]["weight"] == "25%")
        #expect(roundTrip(text + "\nbody"))
    }

    @Test func inboxItem() throws {
        let f = try #require(Frontmatter.parse("---\ncaptured: 2026-09-28T09:12\nsource: phone | quick-capture | share\nkind: task\n---\nEmail Dr. Okafor").frontmatter)
        #expect(f.value(for: "captured") == .dateTime(LocalDateTime(iso: "2026-09-28T09:12")!))
        #expect(f.string(for: "kind") == "task")
    }

    @Test func stableIDIsAddedWithoutTouchingTheRest() throws {
        var f = try #require(Frontmatter.parse(specNote).frontmatter)
        #expect(f.id == nil)
        let before = f.render()
        f.id = "n-9c1e"
        #expect(f.render() == String(before.dropLast(4)) + "id: n-9c1e\n---\n")
        #expect(f.id == "n-9c1e")
    }

    @Test func scalarKinds() throws {
        let f = try #require(Frontmatter.parse("""
        ---
        a: true
        b: False
        c: 42
        d: -3.5
        e: ~
        f:
        g: "true"
        h: 'it''s'
        i: 007x
        j: "esc \\"q\\" \\u00e9 \\n"
        k: 2026-13-40
        ---
        """).frontmatter)
        #expect(f.value(for: "a") == true)
        #expect(f.value(for: "b") == false)
        #expect(f.value(for: "c") == 42)
        #expect(f.value(for: "d") == -3.5)
        #expect(f.value(for: "e") == .null)
        #expect(f.value(for: "f") == .null)
        #expect(f.value(for: "g") == "true")
        #expect(f.value(for: "h") == "it's")
        #expect(f.value(for: "i") == "007x")
        #expect(f.value(for: "j") == "esc \"q\" \u{e9} \n")
        #expect(f.value(for: "k") == "2026-13-40")
    }

    @Test func flowListsAndBlockLists() throws {
        let f = try #require(Frontmatter.parse("""
        ---
        a: [x, "y, z", 'w', [1, 2], {k: v}]
        b:
        - one
        - two   # c
        c:
          - "[[Note]]"
          - key: value
            other: 2
        d: []
        ---
        """).frontmatter)
        #expect(f.value(for: "a") == ["x", "y, z", "w", [1, 2], .map([.init("k", "v")])])
        #expect(f.value(for: "b") == ["one", "two"])
        #expect(f.value(for: "c") == ["[[Note]]", .map([.init("key", "value"), .init("other", 2)])])
        #expect(f.value(for: "d") == .list([]))
    }

    @Test func blockScalar() throws {
        let f = try #require(Frontmatter.parse("---\nsummary: |\n  line one\n  line two\nnext: 1\n---\n").frontmatter)
        #expect(f.string(for: "summary") == "line one\nline two\n")
        #expect(f.number(for: "next") == 1)
    }

    @Test func setReplacesBlockListWithScalarAndBack() throws {
        var f = try #require(Frontmatter.parse("---\ntags:\n  - a\n  - b\nz: 1\n---\n").frontmatter)
        f.set("tags", "solo")
        #expect(f.render() == "---\ntags: solo\nz: 1\n---\n")
        f.set("tags", ["x", "y y", "[[l]]"])
        #expect(f.render() == "---\ntags:\n  - x\n  - y y\n  - \"[[l]]\"\nz: 1\n---\n")
        #expect(f.tags == ["x", "y y", "[[l]]"])
    }

    @Test func setQuotesAmbiguousStrings() throws {
        var f = Frontmatter()
        for s in ["2026-09-24", "true", "12", "a: b", "#x", "", " pad", "[[X]]", "multi\nline", "null"] {
            f.set("k", .string(s))
            let g = try #require(Frontmatter.parse(f.render()).frontmatter)
            #expect(g.value(for: "k") == .string(s), "\(s.debugDescription)")
        }
    }

    @Test func removeKey() throws {
        var f = try #require(Frontmatter.parse(specNote).frontmatter)
        let first = f.remove("due")
        let second = f.remove("due")
        #expect(first)
        #expect(!second)
        #expect(!f.contains("due"))
        #expect(f.render().contains("weight: 25%            # optional\n"))
        f.tags = []
        #expect(!f.contains("tags"))
    }

    @Test func weightAndTypedSetters() throws {
        var f = Frontmatter()
        f.weight = 25
        f.className = "Cell Biology"
        f.kind = .seminar
        f.date = LocalDate(year: 2026, month: 9, day: 24)
        f.tags = ["a", "b"]
        f.session = LocalDateTime(iso: "2026-09-24T10:00")
        let g = try #require(Frontmatter.parse(f.render()).frontmatter)
        #expect(g.weight == 25)
        #expect(g.className == "Cell Biology")
        #expect(g.string(for: "class") == "[[Cell Biology]]")
        #expect(g.kind == .seminar)
        #expect(g.tags == ["a", "b"])
        #expect(g.session?.iso == "2026-09-24T10:00")
        #expect(g.string(for: "weight") == "25%")
        var h = g
        h.weight = nil
        #expect(!h.contains("weight"))
    }

    @Test func typeIsCaseInsensitiveAndUnknownIsNil() throws {
        #expect(try #require(Frontmatter.parse("---\ntype: Lecture\n---\n").frontmatter).kind == .lecture)
        #expect(try #require(Frontmatter.parse("---\ntype: workshop\n---\n").frontmatter).kind == nil)
    }

    @Test func tagsTolerance() throws {
        #expect(try #require(Frontmatter.parse("---\ntags: [a, b]\n---\n").frontmatter).tags == ["a", "b"])
        #expect(try #require(Frontmatter.parse("---\ntags: a, b\n---\n").frontmatter).tags == ["a", "b"])
        #expect(try #require(Frontmatter.parse("---\ntags: \"#a\"\n---\n").frontmatter).tags == ["a"])
    }

    @Test func malformedYamlIsKeptAndReported() throws {
        let text = "---\ngood: 1\nbad: [unclosed\nstray line\n  indented junk\nalso: \"open\n---\nbody"
        let (fm, body) = Frontmatter.parse(text)
        let f = try #require(fm)
        #expect(f.render() + body == text)
        #expect(f.number(for: "good") == 1)
        #expect(f.value(for: "bad") == nil)
        let problems = f.validate()
        #expect(problems.count >= 3)
        #expect(problems.allSatisfy { if case .invalid = $0 { true } else { false } })
    }

    @Test func duplicateKeysAreReportedFirstWins() throws {
        var f = try #require(Frontmatter.parse("---\na: 1\na: 2\n---\n").frontmatter)
        #expect(f.number(for: "a") == 1)
        #expect(f.validate().count == 1)
        f.set("a", 9)
        #expect(f.render() == "---\na: 9\na: 2\n---\n")
    }

    @Test func unicodeAndSpecialKeys() throws {
        var f = try #require(Frontmatter.parse("---\nžluťoučký: kůň 🎓\n---\n").frontmatter)
        #expect(f.string(for: "žluťoučký") == "kůň 🎓")
        f.set("key: with colon", "v")
        f.set("", "empty")
        let g = try #require(Frontmatter.parse(f.render()).frontmatter)
        #expect(g.string(for: "key: with colon") == "v")
        #expect(g.string(for: "") == "empty")
    }

    @Test func subscriptSetsAndRemoves() throws {
        var f = Frontmatter()
        f["a"] = 1
        #expect(f["a"] == 1)
        f["a"] = nil
        #expect(f["a"] == nil)
        #expect(f.render() == "---\n---\n")
    }

    @Test func deepNestingDoesNotCrash() {
        let deep = String(repeating: "[", count: 5000)
        #expect(roundTrip("---\na: \(deep)\n---\n"))
        var lines = "---\na:\n"
        for i in 1..<400 { lines += String(repeating: " ", count: i) + "k:\n" }
        #expect(roundTrip(lines + "---\n"))
        let f = Frontmatter.parse(lines + "---\n").frontmatter
        #expect(f?.value(for: "a") == nil)
    }
}
