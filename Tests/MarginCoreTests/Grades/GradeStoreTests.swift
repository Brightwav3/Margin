import Foundation
import Testing
@testable import MarginCore

@Suite struct GradeStoreTests {
    private let hand = """
        ---
        # my grades
        semester: fall
        grades:
          - {item: Problem set 1, group: Problem sets, weight: 5%, score: 19, max: 20, date: 2026-09-21}
          - {item: "Lab: 1", group: Lab reports, weight: 15, score: 88.5, max: 100}
          - {item: Midterm, date: 2026-10-01}
          - {group: no item}
        tags: [a, b]
        ---

        | Item | Score |
        | --- | --- |
        | Problem set 1 | 19/20 |
        """ + "\n"

    @Test func readsAHandWrittenFile() {
        let items = GradeStore.parse(hand, course: "bio")
        #expect(items.map(\.item) == ["Problem set 1", "Lab: 1", "Midterm"])
        #expect(items[0] == Grade(id: "grade-bio-problem-set-1", courseID: "bio", item: "Problem set 1", group: "Problem sets",
                                  weightPercent: 5, score: 19, max: 20, date: .literal(2026, 9, 21)))
        #expect(items[1].weightPercent == 15 && items[1].score == 88.5)
        #expect(items[2].score == nil && items[2].date == .literal(2026, 10, 1) && items[2].group == nil)
    }

    @Test func appendKeepsEverythingElseByteForByte() throws {
        let new = try GradeStore.appending(Grade(id: "x", courseID: "bio", item: "Quiz 1", group: "Quizzes", score: 7, max: 10),
                                           to: hand, course: "bio", courseName: "Cell Biology")
        let (fmOld, bodyOld) = Frontmatter.parse(hand)
        let (fmNew, bodyNew) = Frontmatter.parse(new)
        #expect(bodyNew == bodyOld)
        #expect(fmNew?.string(for: "semester") == "fall" && fmNew?.list(for: "tags")?.count == 2)
        #expect(new.contains("# my grades"))
        // Only the grades entry changed.
        let oldLines = Set(hand.split(separator: "\n", omittingEmptySubsequences: false))
        #expect(new.split(separator: "\n", omittingEmptySubsequences: false).filter { !oldLines.contains($0) }.count <= 2)
        #expect(fmOld?.keys == fmNew?.keys)
        let items = GradeStore.parse(new, course: "bio")
        #expect(items.count == 4 && items.last?.item == "Quiz 1" && items.last?.score == 7 && items.last?.max == 10)
        #expect(Array(items.prefix(3)) == GradeStore.parse(hand, course: "bio"))
    }

    @Test func roundTripsEveryField() throws {
        let g = Grade(id: "ignored", courseID: "math", item: "Take-home: \"hard\" #2", group: "Homework, weekly", weightPercent: 12,
                      score: 17.25, max: 20, date: .literal(2026, 11, 3))
        let text = try GradeStore.appending(g, to: nil, course: "math", courseName: "Linear Algebra")
        #expect(text.hasPrefix("---\ngrades:") && text.hasSuffix("# Grades — Linear Algebra\n"))
        let expected = Grade(id: "grade-math-take-home-hard-2", courseID: "math", item: g.item, group: g.group, weightPercent: 12, score: 17.25, max: 20, date: g.date)
        #expect(GradeStore.parse(text, course: "math") == [expected])
        // And a second one on top of the first.
        let two = try GradeStore.appending(Grade(id: "", courseID: "math", item: "Pending", date: .literal(2026, 12, 1)), to: text,
                                           course: "math", courseName: "Linear Algebra")
        #expect(GradeStore.parse(two, course: "math").count == 2)
        #expect(Frontmatter.parse(two).body == Frontmatter.parse(text).body)
    }

    @Test func fileWithoutFrontmatterGetsABlockInFront() throws {
        let body = "# Notes about grades\n\nStay calm.\n"
        let new = try GradeStore.appending(Grade(id: "", courseID: "c", item: "A"), to: body, course: "c", courseName: "C")
        #expect(new.hasSuffix(body) && GradeStore.parse(new, course: "c").map(\.item) == ["A"])
    }

    @Test func crlfFilesStayCRLF() throws {
        let crlf = "---\r\ngrades:\r\n  - {item: A, score: 1, max: 2}\r\n---\r\nbody\r\n"
        let new = try GradeStore.appending(Grade(id: "", courseID: "c", item: "B"), to: crlf, course: "c", courseName: "C")
        #expect(!new.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(new.hasSuffix("---\r\nbody\r\n") && GradeStore.parse(new, course: "c").map(\.item) == ["A", "B"])
    }

    @Test func equalSlugsGetNumberedIds() {
        let text = "---\ngrades:\n  - {item: Quiz 1}\n  - {item: quiz-1}\n  - {item: Quiz 1!}\n---\n"
        #expect(GradeStore.parse(text, course: "c").map(\.id) == ["grade-c-quiz-1", "grade-c-quiz-1-2", "grade-c-quiz-1-3"])
    }

    @Test func rejectsWhatIsNotAGrade() {
        func code(_ g: Grade) -> String? { do { _ = try GradeStore.validate(g); return nil } catch let e as MarginError { return e.code } catch { return "other" } }
        #expect(code(Grade(id: "", courseID: "c", item: "")) == "invalid")
        #expect(code(Grade(id: "", courseID: "c", item: "a\nb")) == "invalid")
        #expect(code(Grade(id: "", courseID: "c", item: "a", score: 1, max: -5)) == "invalid")
        #expect(code(Grade(id: "", courseID: "c", item: "a", score: .infinity, max: 5)) == "invalid")
        #expect(code(Grade(id: "", courseID: "c", item: "a", score: 1)) == "invalid")
        #expect(code(Grade(id: "", courseID: "c", item: "a", weightPercent: -1)) == "invalid")
        #expect(code(Grade(id: "", courseID: "c", item: " a ", score: 0, max: 1)) == nil)
    }

    @Test func calculatorAgreesWithTheFile() throws {
        var text: String? = nil
        for g in [Grade(id: "", courseID: "c", item: "P1", group: "HW", score: 8, max: 10),
                  Grade(id: "", courseID: "c", item: "P2", group: "HW", score: 10, max: 10),
                  Grade(id: "", courseID: "c", item: "Exam", group: "Final", score: 70, max: 100)] {
            text = try GradeStore.appending(g, to: text, course: "c", courseName: "C")
        }
        let r = GradeCalculator.course(id: "c", grading: [GradingPart(label: "HW", weightPercent: 40), GradingPart(label: "Final", weightPercent: 60)],
                                       grades: GradeStore.parse(text ?? "", course: "c"))
        #expect(r.percent.map { abs($0 - (0.4 * 90 + 0.6 * 70)) < 1e-9 } == true)
    }
}
