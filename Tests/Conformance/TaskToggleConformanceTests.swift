import Foundation
import Testing
@testable import MarginCore

/// `TaskService.toggle`, run against `FixtureTaskService` and `VaultTaskService` (contract §5).
@Suite struct TaskToggleConformanceTests {
    private func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    @Test(arguments: HarnessKind.allCases)
    func togglingFlipsOneCharacterAndRoundTrips(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = "bio/assignments"
            let before = try await h.rawContent(note)
            let noteBefore = try await h.notes.open(id: note)
            let cs = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: testActor, baseVersion: noteBefore.version,
                                              dryRun: false, idempotencyKey: nil)
            let after = try await h.rawContent(note)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .modified && cs.entries[0].noteID == note)
            #expect(cs.actor == testActor)
            let (a, b) = (Array(before.utf8), Array(after.utf8))
            #expect(a.count == b.count)
            #expect(zip(a, b).filter { $0 != $1 }.count == 1)
            let changed = zip(lines(before), lines(after)).filter { $0 != $1 }
            #expect(changed.count == 1 && changed[0].0.contains("- [x]") && changed[0].1.contains("- [ ]"), "\(changed)")

            // Hashes describe the note versions.
            let noteAfter = try await h.notes.open(id: note)
            #expect(cs.entries[0].beforeHash == noteBefore.version && cs.entries[0].afterHash == noteAfter.version)
            #expect(noteAfter.summary.openTasks == noteBefore.summary.openTasks + 1)

            // The task is open now: it shows up under upcoming (due 30 Sep) and in the course list.
            let upcoming = try await h.tasks.upcoming().map(\.id)
            #expect(upcoming.contains("task-bio-read-chapter-6"))
            let item = try #require(try await h.tasks.tasks(course: "bio").first { $0.id == "task-bio-read-chapter-6" })
            #expect(!item.done)

            // Toggling back restores the file byte for byte.
            _ = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: .user, baseVersion: nil, dryRun: false,
                                         idempotencyKey: nil)
            #expect(try await h.rawContent(note) == before)
            let back = try await h.tasks.upcoming().map(\.id)
            #expect(!back.contains("task-bio-read-chapter-6"))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func checkingATaskRemovesItFromToday(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            #expect(try await h.tasks.today().map(\.id) == ["task-math-problem-set-4"])
            _ = try await h.tasks.toggle(id: "task-math-problem-set-4", actor: .user, baseVersion: nil, dryRun: false,
                                         idempotencyKey: nil)
            #expect(try await h.tasks.today().isEmpty)
            let math = try await h.tasks.tasks(course: "math")
            #expect(math.first { $0.id == "task-math-problem-set-4" }?.done == true)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aTaskWithoutABlockIdIsToggledByItsLocation(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = try await h.notes.open(id: "bio/glossary")
            let text = "# Glossary\n\nprose\n\n```\n- [ ] code, not a task\n```\n\n- [ ] first\n- [ ] second\n"
            _ = try await h.notes.save(id: "bio/glossary", text: text, actor: .user, baseVersion: note.version,
                                       dryRun: false, idempotencyKey: nil)
            let tasks = try await h.tasks.tasks(course: "bio").filter { $0.source.noteID == "bio/glossary" }
            #expect(tasks.map(\.text) == ["first", "second"])
            let second = try #require(tasks.last)
            _ = try await h.tasks.toggle(id: second.id, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let now = try await h.notes.open(id: "bio/glossary").text
            #expect(now == text.replacingOccurrences(of: "- [ ] second", with: "- [x] second"))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func errors(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            func code(_ id: String, base: String? = nil) async -> String? {
                do {
                    _ = try await h.tasks.toggle(id: id, actor: .user, baseVersion: base, dryRun: false, idempotencyKey: nil)
                    return nil
                } catch let error as MarginError { return error.code } catch { return "\(error)" }
            }
            #expect(await code("no-such-task") == "notFound")
            #expect(await code("exam-bio-2026-10-01-midterm") == "invalid")
            let stale = try await h.notes.open(id: "bio/assignments").version
            _ = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: .user, baseVersion: stale, dryRun: false,
                                         idempotencyKey: nil)
            let raw = try await h.rawContent("bio/assignments")
            #expect(await code("task-bio-read-chapter-6", base: stale) == "conflict")
            #expect(try await h.rawContent("bio/assignments") == raw)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func dryRunAndIdempotency(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = "bio/assignments"
            let before = try await h.rawContent(note)
            let version = try await h.notes.open(id: note).version
            let dry = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: testActor, baseVersion: version,
                                               dryRun: true, idempotencyKey: "k-1")
            #expect(dry.isDryRun && dry.entries.count == 1 && dry.entries[0].beforeHash == version)
            #expect(try await h.rawContent(note) == before)

            let first = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: testActor, baseVersion: version,
                                                 dryRun: false, idempotencyKey: "k-1")
            #expect(first.entries[0].afterHash == dry.entries[0].afterHash)
            let written = try await h.rawContent(note)
            // The same key again does not flip the task back.
            let second = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: testActor, baseVersion: nil,
                                                  dryRun: false, idempotencyKey: "k-1")
            #expect(second == first)
            #expect(try await h.rawContent(note) == written)
        }
    }
}
