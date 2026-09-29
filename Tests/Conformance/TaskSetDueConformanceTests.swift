import Foundation
import Testing
@testable import MarginCore

/// `TaskService.setDue`, run against `FixtureTaskService` and `VaultTaskService` (contract §5, M10-10.B).
@Suite struct TaskSetDueConformanceTests {
    private let oct3 = LocalDate.literal(2026, 10, 3)

    private func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    /// The lines that differ between two texts of the same line count.
    private func changed(_ before: String, _ after: String) -> [(String, String)] {
        zip(lines(before), lines(after)).filter { $0 != $1 }
    }

    @Test(arguments: HarnessKind.allCases)
    func replacingADueDateChangesOnlyTheToken(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = "math/assignments", id = "task-math-problem-set-4"
            let before = try await h.rawContent(note)
            let versionBefore = try await h.notes.open(id: note).version
            let cs = try await h.tasks.setDue(id: id, due: oct3, actor: testActor, baseVersion: versionBefore, dryRun: false, idempotencyKey: nil)
            let after = try await h.rawContent(note)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .modified && cs.entries[0].noteID == note && cs.actor == testActor)
            let diff = changed(before, after)
            #expect(diff.count == 1 && diff[0].0 == "- [ ] Problem set 4 @2026-09-28 ^\(id)"
                    && diff[0].1 == "- [ ] Problem set 4 @2026-10-03 ^\(id)", "\(diff)")
            let versionAfter = try await h.notes.open(id: note).version
            #expect(cs.entries[0].beforeHash == versionBefore && cs.entries[0].afterHash == versionAfter)

            // It is not due today any more, but upcoming; the course list shows the new date.
            let today = try await h.tasks.today().map(\.id), upcoming = try await h.tasks.upcoming()
            #expect(!today.contains(id) && upcoming.first { $0.id == id }?.due == oct3)
            let item = try #require(try await h.tasks.tasks(course: "math").first { $0.id == id })
            #expect(item.due == oct3 && item.text == "Problem set 4" && !item.done)
            #expect(item.label == DueLabel.make(due: oct3, today: h.clock.today))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func addingAndRemovingADueDate(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let open = try await h.tasks.tasks(course: "bio").filter { $0.due == nil && !$0.done }
            let task = try #require(open.first)
            let note = task.source.noteID
            let before = try await h.rawContent(note)

            _ = try await h.tasks.setDue(id: task.id, due: oct3, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let added = try await h.rawContent(note)
            let diff = changed(before, added)
            #expect(diff.count == 1 && diff[0].1 == "\(diff[0].0.dropLast(" ^\(task.id)".count)) @2026-10-03 ^\(task.id)", "\(diff)")
            #expect(try await h.tasks.tasks(course: "bio").first { $0.id == task.id }?.due == oct3)

            // Removing puts the file back exactly.
            let cs = try await h.tasks.setDue(id: task.id, due: nil, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1)
            #expect(try await h.rawContent(note) == before)
            #expect(try await h.tasks.tasks(course: "bio").first { $0.id == task.id }?.due == nil)
            // Nothing to remove: nothing written.
            let none = try await h.tasks.setDue(id: task.id, due: nil, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(none.isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func theSameDateWritesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = "chem/assignments"
            let before = try await h.rawContent(note)
            let cs = try await h.tasks.setDue(id: "task-chem-lab-report-tlc", due: .literal(2026, 9, 29), actor: .user,
                                              baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.isEmpty)
            #expect(try await h.rawContent(note) == before)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func dryRunIdempotencyAndErrors(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = "hist/assignments", id = "task-hist-essay-proposal"
            let before = try await h.rawContent(note)
            let version = try await h.notes.open(id: note).version
            let dry = try await h.tasks.setDue(id: id, due: oct3, actor: testActor, baseVersion: version, dryRun: true, idempotencyKey: "k")
            #expect(dry.isDryRun && dry.entries.count == 1 && dry.entries[0].beforeHash == version)
            #expect(try await h.rawContent(note) == before)

            let first = try await h.tasks.setDue(id: id, due: oct3, actor: testActor, baseVersion: version, dryRun: false, idempotencyKey: "k")
            #expect(first.entries[0].afterHash == dry.entries[0].afterHash)
            let written = try await h.rawContent(note)
            let again = try await h.tasks.setDue(id: id, due: .literal(2026, 12, 1), actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: "k")
            #expect(again == first)
            #expect(try await h.rawContent(note) == written)

            func code(_ id: String, base: String? = nil) async -> String? {
                do { _ = try await h.tasks.setDue(id: id, due: oct3, actor: .user, baseVersion: base, dryRun: false, idempotencyKey: nil); return nil }
                catch let e as MarginError { return e.code } catch { return "\(error)" }
            }
            #expect(await code("no-such-task") == "notFound")
            #expect(await code("exam-bio-2026-10-01-midterm") == "invalid")
            #expect(await code("task-math-problem-set-4", base: "stale") == "conflict")
            #expect(try await h.rawContent(note) == written)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func settingADueDateReportsATaskUpdate(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let updates = h.tasks.updates
            _ = try await h.tasks.setDue(id: "task-math-problem-set-4", due: oct3, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let update = await next(from: updates, timeout: 10) { $0.noteIDs.contains("math/assignments") }
            #expect(update?.courseIDs.contains("math") == true)
        }
    }
}
