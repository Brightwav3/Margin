import Foundation
import Testing
@testable import MarginCore

private func codeOf<T>(_ body: () async throws -> T) async -> String? {
    do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other" }
}

private func quiz(_ item: String = "Quiz 1", course: CourseID = "bio", score: Double? = 10, max: Double? = 10) -> Grade {
    Grade(id: "ignored", courseID: course, item: item, group: "Problem sets", weightPercent: 5,
          score: score, max: max, date: .literal(2026, 9, 25))
}

/// `GradeService`, run against `FixtureGradeService` and `VaultGradeService` (contract §5).
@Suite struct GradeServiceConformanceTests {
    @Test(arguments: HarnessKind.allCases)
    func readsTheItemsInOrder(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let items = try await h.grades.grades(course: "bio")
            #expect(items.map(\.item) == ["Problem set 1", "Problem set 2", "Lab 1 report", "Problem set 3", "Midterm", "Final exam"])
            #expect(items[0].score == 19 && items[0].max == 20 && items[0].group == "Problem sets" && items[0].weightPercent == 5)
            #expect(items[3].score == nil && items[3].date == .literal(2026, 10, 2))
            #expect(Set(items.map(\.id)).count == items.count)
            #expect(try await h.grades.grades(course: "chem").isEmpty)
            #expect(await codeOf { try await h.grades.grades(course: "nope") } == "notFound")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func averageIsTheCalculatorsStanding(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let course = try await h.courses.course(id: "bio")
            let items = try await h.grades.grades(course: "bio")
            let expected = GradeCalculator.course(id: "bio", grading: course.grading, grades: items).summary
            #expect(expected != nil)
            #expect(try await h.grades.average(course: "bio") == expected)
            #expect(try await h.grades.average(course: "chem") == nil)
            #expect(await codeOf { try await h.grades.average(course: "nope") } == "notFound")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func addAppendsAndMovesTheAverage(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.grades.gradesVersion(course: "bio")
            let avgBefore = try await h.grades.average(course: "bio")
            let cs = try await h.grades.add(quiz(score: 2, max: 10), actor: testActor, baseVersion: before, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .modified && cs.actor == testActor && !cs.isDryRun)
            #expect(cs.entries[0].path == "Fall 2026/Cell Biology/_grades.md" || kind == .fixture)
            #expect(cs.entries[0].beforeHash == before)
            let after = try await h.grades.gradesVersion(course: "bio")
            #expect(after != before)
            if kind == .vault { #expect(cs.entries[0].afterHash == after) }
            let items = try await h.grades.grades(course: "bio")
            #expect(items.count == 7 && items.last?.item == "Quiz 1" && items.last?.score == 2 && items.last?.max == 10)
            #expect(items.last?.date == .literal(2026, 9, 25) && items.last?.weightPercent == 5)
            #expect(try await h.grades.average(course: "bio") != avgBefore)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func addCreatesTheFileWhenThereIsNone(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let empty = try await h.grades.gradesVersion(course: "chem")
            let cs = try await h.grades.add(quiz(course: "chem"), actor: .user, baseVersion: empty, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .created && cs.entries[0].beforeHash == nil)
            #expect(try await h.grades.grades(course: "chem").map(\.item) == ["Quiz 1"])
            if kind == .vault {
                let text = h.readFile(cs.entries[0].path)
                #expect(text?.hasPrefix("---\ngrades:") == true && text?.contains("item: Quiz 1") == true)
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func dryRunChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.grades.gradesVersion(course: "bio")
            let cs = try await h.grades.add(quiz(), actor: testActor, baseVersion: before, dryRun: true, idempotencyKey: nil)
            #expect(cs.isDryRun && cs.entries.count == 1)
            #expect(try await h.grades.gradesVersion(course: "bio") == before)
            #expect(try await h.grades.grades(course: "bio").count == 6)
            // The real write then produces what the dry run promised.
            let real = try await h.grades.add(quiz(), actor: testActor, baseVersion: before, dryRun: false, idempotencyKey: nil)
            #expect(real.entries == cs.entries)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func staleBaseVersionIsAConflict(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.grades.gradesVersion(course: "bio")
            _ = try await h.grades.add(quiz("Quiz 1"), actor: .user, baseVersion: before, dryRun: false, idempotencyKey: nil)
            #expect(await codeOf { try await h.grades.add(quiz("Quiz 2"), actor: .user, baseVersion: before, dryRun: false, idempotencyKey: nil) } == "conflict")
            #expect(try await h.grades.grades(course: "bio").count == 7)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func repeatedIdempotencyKeyWritesOnce(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let a = try await h.grades.add(quiz(), actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: "k1")
            let b = try await h.grades.add(quiz(), actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: "k1")
            #expect(a == b)
            #expect(try await h.grades.grades(course: "bio").count == 7)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func invalidInputAndDuplicates(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let code = { (g: Grade) async -> String? in await codeOf { try await h.grades.add(g, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) } }
            #expect(await code(quiz("  ")) == "invalid")
            #expect(await code(quiz(score: 5, max: 0)) == "invalid")
            #expect(await code(quiz(score: -1, max: 10)) == "invalid")
            #expect(await code(quiz(score: 5, max: nil)) == "invalid")
            #expect(await code(quiz(score: .nan, max: 10)) == "invalid")
            var heavy = quiz(); heavy.weightPercent = 101
            #expect(await code(heavy) == "invalid")
            #expect(await code(quiz("problem SET 1")) == "conflict")
            #expect(await code(quiz(course: "nope")) == "notFound")
            let count = try await h.grades.grades(course: "bio").count
            #expect(count == 6)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func archivedSemesterIsReadOnly(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(await codeOf { try await h.grades.add(quiz(), actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "readOnly")
            #expect(try await h.grades.grades(course: "bio").count == 6)
        }
    }
}
