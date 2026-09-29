import Foundation
import Testing
@testable import MarginCore

/// AG-03 at the level of the journal and the store: grouping, exact undo, redo, rollback, recovery.
@Suite struct ChangeSetJournalTests {
    static let oldA = nastyBytes("a-old")
    static let newA = nastyBytes("a-new")
    static let oldC = nastyBytes("c-old")
    static let dBytes = nastyBytes("d")
    static let fBytes = nastyBytes("f")
    static let neighbour = Data("untouched\n".utf8)

    static func seed(_ d: TempDir) throws {
        try d.seed("notes/a.md", oldA)
        try d.seed("other/c.md", oldC)
        try d.seed("move/d.md", dBytes)
        try d.seed("gone/f.md", fBytes)
        try d.seed("keep.md", neighbour)
    }

    /// Five operations of every kind on four folders, as one group.
    @Sendable static func multiFileWrite(_ store: VaultStore, _ journal: ChangeSetJournal) async throws -> ChangeSet {
        try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
            try await store.writeData(vp("notes/a.md"), data: newA, expectedVersion: ContentHash(of: oldA))
            try await store.createData(vp("notes/new.md"), data: nastyBytes("n"))
            try await store.writeData(vp("other/c.md"), data: nastyBytes("c-new"), expectedVersion: ContentHash(of: oldC))
            try await store.rename(vp("move/d.md"), to: vp("moved/d.md"))
            try await store.trash(vp("gone/f.md"))
            return []
        }).changeSet
    }

    static var multiFileOld: [String: Data] {
        ["notes/a.md": oldA, "other/c.md": oldC, "move/d.md": dBytes, "gone/f.md": fBytes, "keep.md": neighbour]
    }
    static var multiFileNew: [String: Data] {
        ["notes/a.md": newA, "notes/new.md": nastyBytes("n"), "other/c.md": nastyBytes("c-new"), "moved/d.md": dBytes,
         "keep.md": neighbour]
    }

    // MARK: Recording

    @Test func aTransactionIsRecordedAsOneChangeSetWithAnEntryPerFile() async throws {
        let d = TempDir()
        try Self.seed(d)
        let (store, journal) = try await openJournal(d)
        let cs = try await Self.multiFileWrite(store, journal)
        #expect(d.userFiles() == Self.multiFileNew)
        #expect(cs.entries.map(\.kind) == [.modified, .created, .modified, .moved, .deleted])
        #expect(cs.entries.map(\.path) == ["notes/a.md", "notes/new.md", "other/c.md", "moved/d.md", "gone/f.md"])
        #expect(cs.entries[0].beforeHash == ContentHash(of: Self.oldA).hex && cs.entries[0].afterHash == ContentHash(of: Self.newA).hex)
        #expect(cs.entries[3].fromPath == "move/d.md")
        #expect(await journal.changes(limit: nil) == [cs])
        // Five op files and one committed record.
        #expect(d.journalFiles().filter { $0.contains(".op-") }.count == 5)
        #expect(d.journalFiles().filter { $0.hasSuffix(".meta.json") }.count == 1)
    }

    @Test func aTransactionThatDoesNothingIsNotRecorded() async throws {
        let d = TempDir()
        let (_, journal) = try await openJournal(d)
        let result = try await journal.transaction(actor: .user, idempotencyKey: nil, body: { [] })
        #expect(result.operations.isEmpty)
        #expect(await journal.changes(limit: nil).isEmpty)
        #expect(d.journalFiles().isEmpty)
    }

    @Test func recordsSurviveARestart() async throws {
        let d = TempDir()
        try Self.seed(d)
        let cs: ChangeSet
        do {
            let (store, journal) = try await openJournal(d)
            cs = try await Self.multiFileWrite(store, journal)
        }
        let (_, again) = try await openJournal(d)
        #expect(await again.changes(limit: nil) == [cs])
        #expect(await again.recovery == .init())
        _ = try await again.undo(id: cs.id, actor: .user, mode: .strict, dryRun: false)
        #expect(d.userFiles() == Self.multiFileOld)
    }

    // MARK: Exact undo and redo

    @Test func undoRestoresEveryFileBitForBit() async throws {
        let d = TempDir()
        try Self.seed(d)
        let (store, journal) = try await openJournal(d)
        let cs = try await Self.multiFileWrite(store, journal)
        let undo = try await journal.undo(id: cs.id, actor: .user, mode: .strict, dryRun: false)
        #expect(d.userFiles() == Self.multiFileOld)
        #expect(undo.changeSet.revertsID == cs.id)
        #expect(undo.changeSet.entries.count == 5)
        #expect(Set(undo.changeSet.entries.map(\.kind)) == [.modified, .deleted, .moved, .created])
        // The undone create and the recreated delete leave their copies in the trash, nothing is destroyed.
        #expect(d.snapshot().keys.contains { $0.hasPrefix(".margin/trash/") && $0.hasSuffix("new.md") })
    }

    @Test func redoAppliesTheOriginalAgain() async throws {
        let d = TempDir()
        try Self.seed(d)
        let (store, journal) = try await openJournal(d)
        let cs = try await Self.multiFileWrite(store, journal)
        let undo = try await journal.undo(id: cs.id, actor: .user, mode: .strict, dryRun: false).changeSet
        let redo = try await journal.undo(id: undo.id, actor: .user, mode: .strict, dryRun: false).changeSet
        #expect(d.userFiles() == Self.multiFileNew)
        let again = try await journal.undo(id: redo.id, actor: .user, mode: .strict, dryRun: false).changeSet
        #expect(d.userFiles() == Self.multiFileOld)
        #expect(await journal.changes(limit: nil).map(\.id) == [again.id, redo.id, undo.id, cs.id])
    }

    @Test func undoOfADeleteRecreatesTheFileEvenWhenTheTrashWasEmptied() async throws {
        let d = TempDir()
        try Self.seed(d)
        let (store, journal) = try await openJournal(d)
        let cs = try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
            try await store.trash(vp("gone/f.md")); return []
        }).changeSet
        for (path, _) in d.snapshot() where path.hasPrefix(".margin/trash/") { try FileManager.default.removeItem(at: d.file(path)) }
        _ = try await journal.undo(id: cs.id, actor: .user, mode: .strict, dryRun: false)
        #expect(d.bytes("gone/f.md") == Self.fBytes)
    }

    @Test func undoOfAMovedFolderMovesItBack() async throws {
        let d = TempDir()
        try d.seed("Folder/a.md", nastyBytes("1"))
        try d.seed("Folder/sub/b.md", nastyBytes("2"))
        let (store, journal) = try await openJournal(d)
        let cs = try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
            try await store.rename(vp("Folder"), to: vp("Renamed")); return []
        }).changeSet
        #expect(d.userFiles().keys.sorted() == ["Renamed/a.md", "Renamed/sub/b.md"])
        _ = try await journal.undo(id: cs.id, actor: .user, mode: .strict, dryRun: false)
        #expect(d.userFiles() == ["Folder/a.md": nastyBytes("1"), "Folder/sub/b.md": nastyBytes("2")])
    }

    @Test func aTrashedFolderCannotBeUndoneButNothingIsLost() async throws {
        let d = TempDir()
        try d.seed("Folder/a.md", nastyBytes("1"))
        let (store, journal) = try await openJournal(d)
        let cs = try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
            try await store.trash(vp("Folder")); return []
        }).changeSet
        do { _ = try await journal.undo(id: cs.id, actor: .user, mode: .strict, dryRun: false); Issue.record("must refuse") }
        catch let e as MarginError { #expect(e.code == "invalid") }
        #expect(d.snapshot().contains { $0.key.hasPrefix(".margin/trash/") && $0.key.hasSuffix("Folder/a.md") })
    }

    // MARK: Undo safety

    @Test func aStrictUndoRefusesWhenAnyFileChangedAndTouchesNothing() async throws {
        let d = TempDir()
        try Self.seed(d)
        let (store, journal) = try await openJournal(d)
        let cs = try await Self.multiFileWrite(store, journal)
        // Someone edits the LAST file of the group (the undo would restore the others first).
        try d.seed("other/c.md", Data("edited in Obsidian\n".utf8))
        let before = d.userFiles()
        do { _ = try await journal.undo(id: cs.id, actor: .user, mode: .strict, dryRun: false); Issue.record("must refuse") }
        catch let e as MarginError {
            #expect(e.code == "conflict")
            #expect(e.conflictDetail?.path == "other/c.md")
            #expect(e.conflictDetail?.currentVersion == ContentHash(of: Data("edited in Obsidian\n".utf8)).hex)
        }
        #expect(d.userFiles() == before)                                    // all-or-nothing: notes/a.md was not restored either
        #expect(await journal.changes(limit: nil).map(\.id) == [cs.id])
    }

    @Test func aMergeUndoMergesTextAndRefusesTheRest() async throws {
        let d = TempDir()
        let old = (1...10).map { "l\($0)\n" }.joined()
        let new = old.replacingOccurrences(of: "l2\n", with: "L2\n")
        try d.seed("n.md", Data(old.utf8))
        let (store, journal) = try await openJournal(d)
        let cs = try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
            try await store.write(vp("n.md"), content: new, expectedVersion: ContentHash(of: old)); return []
        }).changeSet
        try d.seed("n.md", Data(new.replacingOccurrences(of: "l9\n", with: "L9\n").utf8))        // later edit elsewhere
        let undo = try await journal.undo(id: cs.id, actor: .user, mode: .merge, dryRun: false)
        #expect(String(decoding: d.bytes("n.md") ?? Data(), as: UTF8.self) == old.replacingOccurrences(of: "l9\n", with: "L9\n"))
        #expect(undo.changeSet.entries.first?.merged == true)
        #expect(undo.changeSet.entries.first?.beforeHash == ContentHash(of: new.replacingOccurrences(of: "l9\n", with: "L9\n")).hex)
    }

    // MARK: Rollback when a group fails

    @Test func aFailureInTheMiddleRollsBackTheWholeGroup() async throws {
        let d = TempDir()
        try Self.seed(d)
        let (store, journal) = try await openJournal(d)
        do {
            _ = try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
                try await store.writeData(vp("notes/a.md"), data: Self.newA, expectedVersion: ContentHash(of: Self.oldA))
                try await store.createData(vp("notes/new.md"), data: nastyBytes("n"))
                try await store.rename(vp("move/d.md"), to: vp("moved/d.md"))
                try await store.trash(vp("gone/f.md"))
                // Fails: stale expected version.
                try await store.writeData(vp("other/c.md"), data: Data("x".utf8), expectedVersion: ContentHash(of: Data("stale".utf8)))
                return []
            })
            Issue.record("must throw")
        } catch let e as MarginError { #expect(e.code == "conflict") }
        #expect(d.userFiles() == Self.multiFileOld)
        #expect(d.journalFiles().isEmpty)                    // no leftover op files, nothing committed
        #expect(await journal.changes(limit: nil).isEmpty)
    }

    @Test func aRollbackNeverOverwritesAChangeMadeByAnotherProgram() async throws {
        let d = TempDir()
        try Self.seed(d)
        let (store, journal) = try await openJournal(d)
        let theirs = Data("their edit\n".utf8)
        do {
            _ = try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
                try await store.writeData(vp("notes/a.md"), data: Self.newA, expectedVersion: ContentHash(of: Self.oldA))
                try d.seed("notes/a.md", theirs)                       // another program edits it right after
                throw MarginError.io("boom")
            })
            Issue.record("must throw")
        } catch let e as MarginError { #expect(e.code == "io") }
        #expect(d.bytes("notes/a.md") == theirs)                       // their edit survives the rollback
    }

    // MARK: Retention on disk

    @Test func expiredRecordsAreRemovedFromDisk() async throws {
        let d = TempDir()
        let clock = MutableClockBox()
        try d.seed("n.md", Data("0\n".utf8))
        let (store, journal) = try await openJournal(d, clock: clock, retention: .init(maxAge: 100, maxCount: 3))
        var version = ContentHash(of: "0\n")
        var ids: [String] = []
        for i in 1...5 {
            let text = "\(i)\n"
            let expected = version
            let cs = try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
                try await store.write(vp("n.md"), content: text, expectedVersion: expected); return []
            }).changeSet
            version = ContentHash(of: text)
            ids.append(cs.id)
        }
        #expect(await journal.changes(limit: nil).map(\.id) == Array(ids.suffix(3).reversed()))
        // Three records of one op file and one meta file each remain; nothing of the two oldest.
        #expect(d.journalFiles().count == 6)
        #expect(!d.journalFiles().contains { $0.contains(ids[0]) || $0.contains(ids[1]) })
        clock.advance(101)
        #expect(await journal.changes(limit: nil).isEmpty)
        #expect(d.journalFiles().isEmpty)
    }

    @Test func aRestartKeepsSequenceNumbersIncreasing() async throws {
        let d = TempDir()
        try d.seed("n.md", Data("0\n".utf8))
        var version = ContentHash(of: "0\n")
        var ids: [String] = []
        for i in 1...3 {
            let (store, journal) = try await openJournal(d)                    // a fresh session each time
            let text = "\(i)\n"
            let expected = version
            ids.append(try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
                try await store.write(vp("n.md"), content: text, expectedVersion: expected); return []
            }).changeSet.id)
            version = ContentHash(of: text)
        }
        let (_, journal) = try await openJournal(d)
        #expect(await journal.changes(limit: nil).map(\.id) == ids.reversed())
    }

    @Test func aDamagedRecordIsReportedAndLeftAlone() async throws {
        let d = TempDir()
        try Self.seed(d)
        let (store, journal) = try await openJournal(d)
        let cs = try await Self.multiFileWrite(store, journal)
        let meta = try #require(d.journalFiles().first { $0.hasSuffix(".meta.json") })
        try d.seed(".margin/changesets/\(meta)", Data("{ not json".utf8))
        let (_, again) = try await openJournal(d)
        #expect(await again.recovery.unreadable.count == 1)
        #expect(await again.changes(limit: nil).isEmpty)
        #expect(d.userFiles() == Self.multiFileNew)                          // the user's files were not touched
        _ = cs
    }
}

/// A clock a test can move (the test module has its own; conformance tests have theirs).
final class MutableClockBox: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = FixedClock().now
    var timeZone: TimeZone { FixedClock.defaultTimeZone }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
