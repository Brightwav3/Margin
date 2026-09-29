import Foundation
import Testing
@testable import MarginCore

/// A clock the test can move.
private final class MovableClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    let timeZone = FixedClock.defaultTimeZone

    init() { current = FixedClock().now }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock() }
}

private let note: NoteID = "bio/lecture-9"

private func codeOf<T>(_ body: () async throws -> T) async -> String? {
    do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other" }
}

/// Replaces the body of the note the way another program would (no automatic snapshot, so these
/// tests control the versions themselves) and returns the new `Note.version`.
@discardableResult
private func save(_ h: Harness, _ text: String) async throws -> String {
    try await h.editNote(note, text)
    return try await h.notes.open(id: note).version
}

/// Saves through `NoteRepository.save`, which takes the automatic `.save` snapshot.
@discardableResult
private func repositorySave(_ h: Harness, _ text: String, dryRun: Bool = false) async throws -> ChangeSet {
    let current = try await h.notes.open(id: note)
    return try await h.notes.save(id: note, text: text, actor: .user, baseVersion: current.version, dryRun: dryRun, idempotencyKey: nil)
}

/// `HistoryService`, run against `FixtureHistoryService` and `VaultHistoryService` (contract §5).
@Suite struct HistoryServiceConformanceTests {
    @Test(arguments: HarnessKind.allCases)
    func aSaveSnapshotIsTakenAtMostOncePerFiveMinutes(kind: HarnessKind) async throws {
        let clock = MovableClock()
        try await withHarness(kind, clock: clock) { h in
            #expect(try await h.history.versions(note: note).isEmpty)
            let first = try await h.history.snapshot(note: note, reason: .save)
            let original = try await h.notes.open(id: note).text
            #expect(first != nil && first?.noteID == note && first?.byteCount == original.utf8.count)
            #expect(try await h.history.text(of: first!) == original)
            // Same text: nothing new, whatever the time.
            clock.advance(3600)
            #expect(try await h.history.snapshot(note: note, reason: .close) == nil)
            // Changed text within five minutes of the newest version: not taken for a save.
            try await save(h, original + "\nmore\n")
            clock.advance(-3600 + 299)
            #expect(try await h.history.snapshot(note: note, reason: .save) == nil)
            clock.advance(2)
            let second = try await h.history.snapshot(note: note, reason: .save)
            #expect(second != nil && second!.timestamp.timeIntervalSince(first!.timestamp) >= 300)
            #expect(try await h.history.text(of: second!) == original + "\nmore\n")
            #expect(try await h.history.versions(note: note).map(\.id) == [second!.id, first!.id])
        }
    }

    // M11-08.B: the save path takes the snapshots itself.

    @Test(arguments: HarnessKind.allCases)
    func savingTwiceWithinFiveMinutesKeepsOneVersion(kind: HarnessKind) async throws {
        let clock = MovableClock()
        try await withHarness(kind, clock: clock) { h in
            #expect(try await h.history.versions(note: note).isEmpty)
            try await repositorySave(h, "# One\n")
            clock.advance(120)
            try await repositorySave(h, "# Two\n")
            let versions = try await h.history.versions(note: note)
            #expect(versions.count == 1)
            #expect(try await h.history.text(of: versions[0]) == "# One\n")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aSaveAfterFiveMinutesAddsAVersion(kind: HarnessKind) async throws {
        let clock = MovableClock()
        try await withHarness(kind, clock: clock) { h in
            try await repositorySave(h, "# One\n")
            clock.advance(301)
            try await repositorySave(h, "# Two\n")
            let versions = try await h.history.versions(note: note)
            #expect(versions.count == 2)
            #expect(try await h.history.text(of: versions[0]) == "# Two\n")
            // A save that changes nothing writes nothing and adds nothing.
            clock.advance(301)
            #expect(try await repositorySave(h, "# Two\n").isEmpty)
            #expect(try await h.history.versions(note: note).count == 2)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aDryRunSaveTakesNoSnapshot(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let dry = try await repositorySave(h, "# Dry\n", dryRun: true)
            #expect(dry.isDryRun && dry.entries.count == 1)
            #expect(try await h.history.versions(note: note).isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aRestoreDoesNotAddAnAutomaticSnapshotOnTop(kind: HarnessKind) async throws {
        let clock = MovableClock()
        try await withHarness(kind, clock: clock) { h in
            try await repositorySave(h, "# Old\n")
            let old = try await h.history.versions(note: note)[0]
            clock.advance(400)
            try await repositorySave(h, "# New\n")
            #expect(try await h.history.versions(note: note).count == 2)
            clock.advance(400)
            let base = try await h.notes.open(id: note).version
            _ = try await h.history.restore(old, actor: testActor, baseVersion: base, dryRun: false, idempotencyKey: nil)
            let texts = try await h.history.versions(note: note).asyncMap { try await h.history.text(of: $0) }
            #expect(texts == ["# Old\n", "# New\n", "# Old\n"])   // the restore records the restored text once
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func closeSnapshotIgnoresTheLimitButNotIdenticalText(kind: HarnessKind) async throws {
        let clock = MovableClock()
        try await withHarness(kind, clock: clock) { h in
            _ = try await h.history.snapshot(note: note, reason: .save)
            try await save(h, "# Changed\n")
            clock.advance(10)
            #expect(try await h.history.snapshot(note: note, reason: .save) == nil)
            let closed = try await h.history.snapshot(note: note, reason: .close)
            #expect(closed != nil)
            #expect(try await h.history.snapshot(note: note, reason: .close) == nil)
            #expect(try await h.history.versions(note: note).count == 2)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func unknownNotes(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let none = try await h.history.versions(note: "nope/none")
            #expect(none.isEmpty)
            #expect(await codeOf { try await h.history.snapshot(note: "nope/none", reason: .close) } == "notFound")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func twentyVersionsAreAllKeptAndReadable(kind: HarnessKind) async throws {
        let clock = MovableClock()
        try await withHarness(kind, clock: clock) { h in
            var texts: [String] = []
            for i in 1...20 {
                let text = "# Lecture 9\n\nVersion \(i)\n" + String(repeating: "line\n", count: i)
                try await save(h, text)
                texts.append(text)
                #expect(try await h.history.snapshot(note: note, reason: .save) != nil)
                clock.advance(301)
            }
            let versions = try await h.history.versions(note: note)
            #expect(versions.count == 20)
            #expect(zip(versions, versions.dropFirst()).allSatisfy { $0.timestamp > $1.timestamp })
            for (v, text) in zip(versions.reversed(), texts) { #expect(try await h.history.text(of: v) == text) }
            // Restoring an old one deletes nothing.
            let oldest = versions.last!
            let base = try await h.notes.open(id: note).version
            _ = try await h.history.restore(oldest, actor: testActor, baseVersion: base, dryRun: false, idempotencyKey: nil)
            let after = try await h.history.versions(note: note)
            #expect(Set(versions.map(\.id)).isSubset(of: Set(after.map(\.id))))
            #expect(try await h.notes.open(id: note).text == texts[0])
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func retentionKeepsTheNewestFiftyOrThirtyDaysWhicheverIsMore(kind: HarnessKind) async throws {
        let clock = MovableClock()
        try await withHarness(kind, clock: clock) { h in
            // 60 versions an hour apart are all within 30 days: all kept.
            for i in 1...60 {
                try await save(h, "# v\(i)\n")
                _ = try await h.history.snapshot(note: note, reason: .close)
                clock.advance(3600)
            }
            #expect(try await h.history.versions(note: note).count == 60)
            // Jump 40 days: the next snapshot finds 60 old versions, only the newest 50 stay.
            clock.advance(40 * 86_400)
            try await save(h, "# later\n")
            _ = try await h.history.snapshot(note: note, reason: .close)
            let versions = try await h.history.versions(note: note)
            #expect(versions.count == 50)
            #expect(try await h.history.text(of: versions[0]) == "# later\n")
            #expect(try await h.history.text(of: versions[1]) == "# v60\n")
            // The dropped ones are gone, and say so.
            let dropped = NoteVersion(id: "\(note)@" + HistoryEngine.stem(Int(FixedClock().now.timeIntervalSince1970 * 1000)),
                                      noteID: note, timestamp: FixedClock().now, byteCount: 1)
            #expect(await codeOf { try await h.history.text(of: dropped) } == "notFound")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func diffShowsTheLines(kind: HarnessKind) async throws {
        let clock = MovableClock()
        try await withHarness(kind, clock: clock) { h in
            try await save(h, "one\ntwo\nthree\n")
            let a = try await h.history.snapshot(note: note, reason: .close)!
            try await save(h, "one\n2\nthree\nfour\n")
            let b = try await h.history.snapshot(note: note, reason: .close)!
            let d = try await h.history.diff(a, b)
            #expect(d.lines.map(\.kind) == [.equal, .removed, .added, .equal, .added])
            #expect(d.lines.map(\.text) == ["one", "two", "2", "three", "four"])
            #expect(d.addedCount == 2 && d.removedCount == 1 && !d.isIdentical)
            #expect(try await h.history.diff(a, a).isIdentical)
            try await save(h, "one\n2\nthree\nfive\n")
            let now = try await h.history.diffWithCurrent(b)
            #expect(now.addedCount == 1 && now.removedCount == 1)
            let other = NoteVersion(id: "x@0000000000001", noteID: "bio/lab-2", timestamp: Date(timeIntervalSince1970: 0.001), byteCount: 0)
            #expect(await codeOf { try await h.history.diff(a, other) } == "invalid")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func restoreWritesTheOldTextAsANewSave(kind: HarnessKind) async throws {
        let clock = MovableClock()
        try await withHarness(kind, clock: clock) { h in
            try await save(h, "# Old\nkeep me\n")
            let old = try await h.history.snapshot(note: note, reason: .close)!
            clock.advance(60)
            let edited = try await save(h, "# New\nunsaved-in-history\n")
            // The current text has no version yet; restore must not lose it.
            let dry = try await h.history.restore(old, actor: testActor, baseVersion: edited, dryRun: true, idempotencyKey: nil)
            #expect(dry.isDryRun && dry.entries.count == 1 && dry.entries[0].kind == .modified)
            #expect(try await h.notes.open(id: note).text == "# New\nunsaved-in-history\n")
            #expect(try await h.history.versions(note: note).count == 1)

            #expect(await codeOf { try await h.history.restore(old, actor: testActor, baseVersion: "stale", dryRun: false, idempotencyKey: nil) } == "conflict")
            #expect(try await h.notes.open(id: note).text == "# New\nunsaved-in-history\n")

            let cs = try await h.history.restore(old, actor: testActor, baseVersion: edited, dryRun: false, idempotencyKey: "r1")
            #expect(cs.actor == testActor && cs.entries.count == 1 && cs.entries[0].beforeHash == edited)
            #expect(try await h.notes.open(id: note).text == "# Old\nkeep me\n")
            let texts = try await h.history.versions(note: note).asyncMap { try await h.history.text(of: $0) }
            #expect(texts.contains("# New\nunsaved-in-history\n") && texts.contains("# Old\nkeep me\n"))
            #expect(texts.first == "# Old\nkeep me\n" && texts.count == 3)
            // The same key again: the first result, nothing more written.
            let again = try await h.history.restore(old, actor: testActor, baseVersion: edited, dryRun: false, idempotencyKey: "r1")
            #expect(again == cs)
            #expect(try await h.history.versions(note: note).count == 3)
            // Restoring what is current changes nothing.
            let now = try await h.notes.open(id: note).version
            #expect(try await h.history.restore(old, actor: .user, baseVersion: now, dryRun: false, idempotencyKey: nil).isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func vaultKeepsSnapshotsUnderMarginHistory(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.history.snapshot(note: note, reason: .close)
            let files = h.listFiles(".margin/history/bio%2Flecture-9")
            #expect(kind == .vault ? files.count == 1 && files[0].hasSuffix(".snap") : files.isEmpty)
        }
    }
}

extension Sequence {
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for e in self { out.append(try await transform(e)) }
        return out
    }
}
