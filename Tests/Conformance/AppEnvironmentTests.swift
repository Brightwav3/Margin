import Foundation
import Testing
@testable import MarginCore

/// `AppEnvironment` is the only thing the UI needs from the backend: both flavours build, shut
/// down cleanly and cope with vaults that are empty or were not made by Margin.
@Suite struct AppEnvironmentTests {
    static let vaults = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/vaults", isDirectory: true)

    @Test func fixtureEnvironmentUsesTheGivenClock() async throws {
        let clock = FixedClock(local: LocalDateTime(date: .literal(2026, 10, 1), time: .literal(8, 0)))
        let env = AppEnvironment.fixture(clock: clock)
        #expect(env.clock.today == .literal(2026, 10, 1))
        let today = try await env.tasks.today()
        #expect(today.contains { $0.id == "exam-bio-2026-10-01-midterm" })
        let defaults = AppEnvironment.fixture()
        #expect(defaults.clock.today == Fixtures.today)
        await env.shutdown()
        await defaults.shutdown()
    }

    @Test func shutdownEndsTheUpdateStreams() async throws {
        for kind in HarnessKind.allCases {
            let h = try await Harness.make(kind)
            let updates = h.courses.updates
            let changes = h.notes.externalChanges
            await h.shutdown()
            // Both streams finish instead of hanging (the helper would return nil on a timeout, so
            // measure that iteration ends by itself).
            var n = 0
            for await _ in updates { n += 1 }
            for await _ in changes { n += 1 }
            #expect(n == 0, "\(kind)")
            // Reads still work after shutdown.
            let courses = try await h.courses.courses(query: nil)
            #expect(courses.count == 6)
        }
    }

    @Test func vaultEnvironmentOpensTheCommittedWeek5Vault() async throws {
        let env = try await AppEnvironment.vault(at: Self.vaults.appendingPathComponent("week5"), clock: FixedClock())
        let courses = try await env.courses.courses(query: nil)
        #expect(courses.map(\.id) == Fixtures.week5.courses.map(\.id).sorted { a, b in
            Fixtures.week5.course(a)!.name < Fixtures.week5.course(b)!.name
        })
        let today = try await env.tasks.today()
        #expect(today.map(\.id) == ["task-math-problem-set-4"])
        await env.shutdown()
    }

    @Test func aMissingVaultFolderIsNotFound() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-vault-\(UUID().uuidString)")
        do {
            _ = try await AppEnvironment.vault(at: missing, clock: FixedClock())
            Issue.record("should throw")
        } catch let e as MarginError { #expect(e.code == "notFound") }
    }

    @Test func anEmptyVaultHasNothingAndNoSemester() async throws {
        let env = try await AppEnvironment.vault(at: Self.vaults.appendingPathComponent("empty"), clock: FixedClock())
        #expect(try await env.courses.courses(query: nil).isEmpty)
        #expect(try await env.courses.semesters().isEmpty)
        #expect(try await env.notes.notes(course: nil).isEmpty)
        #expect(try await env.tasks.today().isEmpty)
        #expect(try await env.tasks.upcoming().isEmpty)
        do { _ = try await env.courses.sessions(week: 1); Issue.record("no semester, should throw") }
        catch let e as MarginError { #expect(e.code == "notFound") }
        await env.shutdown()
    }

    @Test func aForeignObsidianVaultIsReadableAsNotesWithoutCourses() async throws {
        let env = try await AppEnvironment.vault(at: Self.vaults.appendingPathComponent("obsidian-quirks"), clock: FixedClock())
        let notes = try await env.notes.notes(course: nil)
        #expect(notes.count == 13)
        #expect(notes.allSatisfy { $0.courseID == nil })
        #expect(try await env.courses.courses(query: nil).isEmpty)
        // Notes without an `id:` are addressed by their path.
        let chapter = try await env.notes.open(id: "Projects/Thesis/Chapter 1")
        #expect(chapter.text.hasPrefix("# Chapter 1"))
        #expect(!chapter.text.contains("status: draft"))
        // Not a note: underscore files do not exist here, other file types are ignored.
        #expect(!notes.contains { $0.title.contains("Not markdown") })
        // Tasks need a course, so none of the vault's tasks appear as course tasks.
        #expect(try await env.tasks.today().isEmpty)
        await env.shutdown()
    }
}
