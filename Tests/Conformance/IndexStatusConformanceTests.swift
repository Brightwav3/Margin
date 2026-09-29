import Foundation
import Testing
@testable import MarginCore

/// In-memory note source: `count` notes, some of which cannot be read.
private struct FakeSource: NoteContentSource {
    let count: Int
    var unreadable: Set<Int> = []
    func listMarkdown() async throws -> [String] { (0..<count).map { "Fall 2026/Bio/Note \($0).md" } }
    func read(_ path: String) async throws -> String {
        let n = Int(path.split(separator: " ").last?.dropLast(3) ?? "") ?? -1
        if unreadable.contains(n) { throw MarginError.notFound(path) }
        return "---\nid: n\(n)\n---\n# Note \(n)\n- [ ] task \(n)\n"
    }
}

private func assertMonotonic(_ seen: [IndexProgress], sourceLocation: SourceLocation = #_sourceLocation) {
    let percents = seen.map(\.percent)
    #expect(percents == percents.sorted(), "never decreases", sourceLocation: sourceLocation)
    #expect(Set(percents).count == percents.count, "each percent once", sourceLocation: sourceLocation)
    #expect(percents.allSatisfy { (0...100).contains($0) }, sourceLocation: sourceLocation)
    #expect(seen.dropLast().allSatisfy { !$0.isComplete && $0.percent < 100 }, "only the last is complete",
            sourceLocation: sourceLocation)
    #expect(seen.last?.isComplete == true && seen.last?.percent == 100, sourceLocation: sourceLocation)
    #expect(seen.map(\.filesDone) == seen.map(\.filesDone).sorted(), sourceLocation: sourceLocation)
}

/// `IndexStatus` (M11-07.B): the fixture and the vault, plus the index build itself.
@Suite struct IndexStatusConformanceTests {
    @Test(arguments: HarnessKind.allCases)
    func aStreamGivesTheFinishedStateAndEnds(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            // Ends on its own: `collect` returns when the stream ends, or at the complete element.
            var seen: [IndexProgress] = []
            for await p in h.indexStatus.progress { seen.append(p) }
            let last = try #require(seen.last)
            #expect(last.isComplete && last.percent == 100 && last.filesDone == last.filesTotal)
            #expect(last.filesTotal > 0, "the sample has notes")
            assertMonotonic(seen)
            // A second, later subscriber gets it too.
            var again: [IndexProgress] = []
            for await p in h.indexStatus.progress { again.append(p) }
            #expect(again == seen)
        }
    }

    @Test func fixtureIsCompleteAtOnce() async throws {
        let env = AppEnvironment.fixture()
        var seen: [IndexProgress] = []
        for await p in env.indexStatus.progress { seen.append(p) }
        #expect(seen.count == 1 && seen[0].percent == 100 && seen[0].isComplete)
        #expect(seen[0].filesTotal == Fixtures.week5.allNotes.count)
        await env.shutdown()
    }

    @Test func vaultTotalIsTheNumberOfNotesOnDisk() async throws {
        try await withHarness(.vault) { h in
            let notes = try await h.notes.notes(course: nil).count
            var last: IndexProgress?
            for await p in h.indexStatus.progress { last = p }
            // Notes plus `_course.md` and other files the index reads; at least all notes.
            #expect((last?.filesTotal ?? 0) >= notes)
        }
    }

    @Test func buildReportsEveryPercentFromZeroToHundred() async throws {
        let tracker = IndexProgressTracker()
        let stream = tracker.subscribe()      // before the build: sees the whole run
        let index = NoteIndex(clock: FixedClock())
        try await index.build(from: FakeSource(count: 400)) { tracker.report(done: $0, total: $1) }
        tracker.finish()
        var seen: [IndexProgress] = []
        for await p in stream { seen.append(p) }
        assertMonotonic(seen)
        #expect(seen.first?.percent == 0 && seen.first?.filesTotal == 400)
        #expect(seen.map(\.percent) == Array(0...100), "400 files: every whole percent, once")
        #expect(seen.last?.filesDone == 400)
        #expect(await index.allNotes.count == 400)
    }

    @Test func unreadableFilesStillCountAsDone() async throws {
        let tracker = IndexProgressTracker()
        let stream = tracker.subscribe()
        let index = NoteIndex(clock: FixedClock())
        let failures = try await index.build(from: FakeSource(count: 30, unreadable: [3, 4, 29])) {
            tracker.report(done: $0, total: $1)
        }
        tracker.finish()
        #expect(failures.count == 3)
        var seen: [IndexProgress] = []
        for await p in stream { seen.append(p) }
        assertMonotonic(seen)
        #expect(seen.last?.filesDone == 30 && seen.last?.filesTotal == 30)
    }

    @Test func fewFilesGiveFewSteps() async throws {
        let tracker = IndexProgressTracker()
        let stream = tracker.subscribe()
        try await NoteIndex(clock: FixedClock()).build(from: FakeSource(count: 3)) { tracker.report(done: $0, total: $1) }
        tracker.finish()
        var seen: [IndexProgress] = []
        for await p in stream { seen.append(p) }
        assertMonotonic(seen)
        #expect(seen.map(\.percent) == [0, 33, 66, 99, 100])
    }

    @Test func emptyIndexIsCompleteAtOnce() async throws {
        let tracker = IndexProgressTracker()
        let stream = tracker.subscribe()
        try await NoteIndex(clock: FixedClock()).build(from: FakeSource(count: 0)) { tracker.report(done: $0, total: $1) }
        tracker.finish()
        var seen: [IndexProgress] = []
        for await p in stream { seen.append(p) }
        assertMonotonic(seen)
        #expect(seen.last == IndexProgress(filesDone: 0, filesTotal: 0, isComplete: true))
        // Late subscriber: only the finished state.
        var late: [IndexProgress] = []
        for await p in tracker.subscribe() { late.append(p) }
        #expect(late.count == 1 && late[0].percent == 100)
    }

    @Test func vaultCallbackSeesTheBuildFromZeroToHundred() async throws {
        let folder = TempFolder()
        let store = try await VaultStore.open(root: folder.url, trash: PortableTrash(), createIfMissing: true)
        try await SampleVaultGenerator.generate(into: store, from: Fixtures.week5)
        let collected = Collected()
        let env = try await AppEnvironment.vault(at: folder.url, clock: FixedClock(), watchInterval: 0.05) { collected.add($0) }
        let seen = collected.all
        assertMonotonic(seen)
        #expect(seen.first?.percent == 0 && seen.last?.percent == 100)
        #expect((seen.last?.filesTotal ?? 0) > 0)
        await env.shutdown()
    }

    @Test func emptyVaultIsCompleteAtOnce() async throws {
        let folder = TempFolder()
        try await SemesterFactory.initializeVault(
            at: folder.url, firstSemester: NewSemester(name: "Fall 2026", start: .literal(2026, 8, 31), end: .literal(2026, 12, 13)))
        let collected = Collected()
        let env = try await AppEnvironment.vault(at: folder.url, clock: FixedClock(), watchInterval: 0.05) { collected.add($0) }
        assertMonotonic(collected.all)
        #expect(collected.all.last == IndexProgress(filesDone: 0, filesTotal: 0, isComplete: true))
        var seen: [IndexProgress] = []
        for await p in env.indexStatus.progress { seen.append(p) }
        #expect(seen.count == 1 && seen[0].percent == 100)
        await env.shutdown()
    }

    @Test func progressValuesAreClampedAndCodable() throws {
        let p = IndexProgress(filesDone: 50, filesTotal: 10)
        #expect(p.filesDone == 10 && p.percent == 99 && !p.isComplete)
        #expect(IndexProgress(filesDone: -5, filesTotal: 10).filesDone == 0)
        let decoded = try JSONDecoder().decode(IndexProgress.self, from: JSONEncoder().encode(IndexProgress(filesDone: 3, filesTotal: 3, isComplete: true)))
        #expect(decoded.percent == 100)
    }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [IndexProgress] = []
    func add(_ p: IndexProgress) { lock.lock(); items.append(p); lock.unlock() }
    var all: [IndexProgress] { lock.lock(); defer { lock.unlock() }; return items }
}
