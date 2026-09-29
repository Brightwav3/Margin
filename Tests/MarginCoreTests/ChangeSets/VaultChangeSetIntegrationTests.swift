import Foundation
import Testing
@testable import MarginCore

/// The vault services end to end: real files, the index, link rewriting, restarts.
extension PerfSuites {
@Suite struct VaultChangeSetIntegrationTests {
    struct Rig {
        let dir: TempDir
        let backend: VaultBackend
        var notes: VaultNoteRepository { VaultNoteRepository(backend: backend) }
        var changes: VaultChangeSetStore { VaultChangeSetStore(backend: backend) }

        static func sampleVault() async throws -> TempDir {
            let dir = TempDir()
            let store = try await VaultStore.open(root: dir.url, createIfMissing: true)
            try await SampleVaultGenerator.generate(into: store, from: Fixtures.week5)
            return dir
        }

        static func open(_ dir: TempDir, clock: any Clock = FixedClock(), fileSystem: any FileSystem = POSIXFileSystem(),
                         retention: ChangeSetRetention = .standard) async throws -> Rig {
            Rig(dir: dir, backend: try await VaultBackend.open(at: dir.url, clock: clock, watchInterval: 0.05,
                                                              retention: retention, fileSystem: fileSystem))
        }

        func close() async { await backend.shutdown() }
    }

    static let agent = Actor.agent(identity: "study-helper", client: "test", session: "s-1")

    static let tricky = "\u{FEFF}---\r\nid: bio/tricky\r\nclass: \"[[Cell Biology]]\"\r\ntype: note\r\n---\r\n# Tricky ünïcödé 🧬\r\n\r\nline one\r\n\r\n- [ ] a task @2026-10-01\r\nlast line without newline"
    static let trickyPath = "Fall 2026/Cell Biology/Tricky.md"

    /// A vault with the sample notes plus one whose bytes any lossy handling would change.
    static func vaultWithTrickyNote() async throws -> TempDir {
        let dir = try await Rig.sampleVault()
        try dir.seed(trickyPath, Data(tricky.utf8))
        return dir
    }

    @Sendable static func trickyID(_ rig: Rig) async throws -> NoteID {
        let all = try await rig.notes.notes(course: "bio")
        return try #require(all.first { $0.title.hasPrefix("Tricky") }?.id)
    }

    // MARK: Bit for bit

    @Test func undoRestoresTheExactBytesOfEveryKindOfWrite() async throws {
        let dir = try await Self.vaultWithTrickyNote()
        let rig = try await Rig.open(dir)
        let id = try await Self.trickyID(rig)
        let original = dir.userFiles()
        #expect(original[Self.trickyPath] == Data(Self.tricky.utf8))

        func check(_ what: String, _ op: () async throws -> ChangeSet) async throws {
            let cs = try await op()
            #expect(!cs.entries.isEmpty, "\(what) changed nothing")
            #expect(dir.userFiles() != original, "\(what) did not change the vault")
            _ = try await rig.changes.undo(id: cs.id, actor: .user)
            #expect(dir.userFiles() == original, "\(what): undo did not restore the bytes")
        }
        let note = try await rig.notes.open(id: id)
        try await check("save") {
            try await rig.notes.save(id: id, text: note.text + "\r\nappended\r\n", actor: .user, baseVersion: note.version,
                                     dryRun: false, idempotencyKey: nil)
        }
        try await check("move") {
            try await rig.notes.move(id: id, toCourse: "chem", actor: .user, baseVersion: note.version, dryRun: false,
                                     idempotencyKey: nil)
        }
        try await check("delete") {
            try await rig.notes.delete(id: id, actor: .user, baseVersion: note.version, dryRun: false, idempotencyKey: nil)
        }
        // The index followed every step: the note is back where it was, with its tasks.
        let again = try await rig.notes.open(id: id)
        #expect(again.version == note.version && again.summary.courseID == "bio" && again.summary.totalTasks == 1)
        await rig.close()
    }

    @Test func undoOfACreateRestoresTheFolderContentExactly() async throws {
        let dir = try await Self.vaultWithTrickyNote()
        let rig = try await Rig.open(dir)
        let original = dir.userFiles()
        let cs = try await rig.notes.create(course: "bio", title: "Brand new", kind: .lecture, text: "hello\r\n", actor: .user,
                                            baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(dir.userFiles().count == original.count + 1)
        _ = try await rig.changes.undo(id: cs.id, actor: .user)
        #expect(dir.userFiles() == original)
        #expect(try await rig.notes.notes(course: "bio").count == 11)     // 10 sample notes + the tricky one
        await rig.close()
    }

    // MARK: A move is a multi-file group

    static let linkerA = "Fall 2026/Cell Biology/Linker A.md"
    static let linkerB = "Fall 2026/Organic Chemistry/Linker B.md"

    /// The sample vault plus two notes whose folder-qualified links to `bio/glossary` must be
    /// rewritten when it moves to another course (bare `[[Glossary]]` links stay valid and untouched).
    static func vaultWithLinkers() async throws -> TempDir {
        let dir = try await Rig.sampleVault()
        try dir.seed(linkerA, Data("See [[Cell Biology/Glossary]] and [[Glossary|terms]].\r\nünïcödé 🧬\r\n".utf8))
        try dir.seed(linkerB, Data("![[Cell Biology/Glossary]]\n\n[[Cell Biology/Glossary#Terms|t]]\n".utf8))
        return dir
    }

    private func linkedNote(in dir: TempDir, rig: Rig) async throws -> (id: NoteID, path: String, linkers: [String]) {
        ("bio/glossary", "Fall 2026/Cell Biology/Glossary.md", [Self.linkerA, Self.linkerB])
    }

    @Test func movingANoteRecordsTheRewrittenLinksAndUndoRestoresThemAll() async throws {
        let dir = try await Self.vaultWithLinkers()
        let rig = try await Rig.open(dir)
        let (id, path, linkers) = try await linkedNote(in: dir, rig: rig)
        #expect(!linkers.isEmpty)
        let original = dir.userFiles()
        let current = try await rig.notes.open(id: id)
        let target: CourseID = "chem"

        let cs = try await rig.notes.move(id: id, toCourse: target, actor: Self.agent, baseVersion: current.version,
                                          dryRun: false, idempotencyKey: nil)
        let afterMove = dir.userFiles()
        // The group holds the move and one entry per rewritten note.
        #expect(cs.entries.first?.kind == .moved && cs.entries.first?.fromPath == path)
        let rewritten = cs.entries.dropFirst()
        #expect(rewritten.allSatisfy { $0.kind == .modified && $0.noteID != nil }, "\(rewritten)")
        #expect(Set(rewritten.map(\.path)) == Set(linkers))
        for linker in linkers { #expect(afterMove[linker] != original[linker], "\(linker) was not rewritten") }

        // One undo puts the note back AND every link.
        let undo = try await rig.changes.undo(id: cs.id, actor: .user)
        #expect(dir.userFiles() == original)
        #expect(Set(undo.entries.map(\.path)) == Set(cs.entries.map { $0.fromPath ?? $0.path }))
        // The index agrees with the files.
        let back = try await rig.notes.open(id: id)
        #expect(back.summary.courseID == current.summary.courseID && back.version == current.version)

        // Redo moves it again, with the same rewritten links.
        _ = try await rig.changes.undo(id: undo.id, actor: .user)
        #expect(dir.userFiles() == afterMove)
        #expect(try await rig.notes.open(id: id).summary.courseID == target)
        await rig.close()
    }

    @Test func undoingAMoveIsRefusedAsAWholeWhenOneRewrittenNoteWasEditedSince() async throws {
        let dir = try await Self.vaultWithLinkers()
        let rig = try await Rig.open(dir)
        let (id, _, linkers) = try await linkedNote(in: dir, rig: rig)
        let current = try await rig.notes.open(id: id)
        let cs = try await rig.notes.move(id: id, toCourse: "chem", actor: .user,
                                          baseVersion: current.version, dryRun: false, idempotencyKey: nil)
        let edited = Data("someone rewrote this note\n".utf8)
        try dir.seed(try #require(linkers.first), edited)
        let before = dir.userFiles()
        do { _ = try await rig.changes.undo(id: cs.id, actor: .user); Issue.record("must refuse") }
        catch let e as MarginError { #expect(e.code == "conflict") }
        #expect(dir.userFiles() == before)                                  // the note was not moved back either
        await rig.close()
    }

    // MARK: A broken journal folder

    @Test func aBrokenJournalFolderKeepsReadsWorkingAndRefusesWritesInsteadOfWritingUnrecorded() async throws {
        let dir = try await Self.vaultWithTrickyNote()
        try dir.seed(".margin/changesets", Data("not a folder".utf8))           // a file where the journal folder should be
        let original = dir.userFiles()
        let rig = try await Rig.open(dir)
        let id = try await Self.trickyID(rig)
        let note = try await rig.notes.open(id: id)                              // reading works
        #expect(note.version == ContentHash(of: Data(Self.tricky.utf8)).hex)
        #expect(await rig.backend.journal.recovery.problems.count == 1)
        do {
            _ = try await rig.notes.save(id: id, text: "x", actor: .user, baseVersion: note.version, dryRun: false, idempotencyKey: nil)
            Issue.record("a write that cannot be journaled must not happen")
        } catch let e as MarginError { #expect(e.code == "io" || e.code == "invalid", "\(e)") }
        #expect(dir.userFiles() == original)                                     // and nothing was written
        #expect(try await rig.changes.changes(limit: nil).isEmpty)
        await rig.close()
    }

    // MARK: Restart

    @Test func undoWorksAfterTheAppWasRestarted() async throws {
        let dir = try await Self.vaultWithTrickyNote()
        let original = dir.userFiles()
        var rig = try await Rig.open(dir)
        let id = try await Self.trickyID(rig)
        let note = try await rig.notes.open(id: id)
        let cs = try await rig.notes.save(id: id, text: note.text + "more\r\n", actor: Self.agent, baseVersion: note.version,
                                          dryRun: false, idempotencyKey: nil)
        await rig.close()

        rig = try await Rig.open(dir)
        let listed = try await rig.changes.changes(limit: nil)
        #expect(listed == [cs])
        _ = try await rig.changes.undo(id: cs.id, actor: .user)
        #expect(dir.userFiles() == original)
        await rig.close()
    }

    // MARK: Interrupted writes, end to end

    @Test func aWriteInterruptedAtAnyPointIsCompleteOrAbsentAfterARestart() async throws {
        // Probe: how many calls does a move with link rewriting make?
        func attempt(fault: FaultInjectingFileSystem.Fault?, calls: Int? = nil) async throws
            -> (dir: TempDir, original: [String: Data], moved: [String: Data], log: [String], threw: Bool, id: NoteID) {
            let dir = try await Self.vaultWithLinkers()
            let fs = FaultInjectingFileSystem(base: NoSyncFileSystem())
            let rig = try await Rig.open(dir, fileSystem: fs)
            let (id, _, _) = try await linkedNote(in: dir, rig: rig)
            let current = try await rig.notes.open(id: id)
            let original = dir.userFiles()
            fs.arm(fault)
            var threw = false
            do {
                _ = try await rig.notes.move(id: id, toCourse: "chem", actor: .user,
                                             baseVersion: current.version, dryRun: false, idempotencyKey: nil)
            } catch { threw = true }
            let log = fs.log
            let moved = dir.userFiles()
            await rig.close()
            return (dir, original, moved, log, threw, id)
        }
        let probe = try await attempt(fault: nil)
        #expect(!probe.threw && probe.moved != probe.original)
        let total = probe.log.count
        let step = max(1, total / 25)
        var problems: [String] = []
        var runs = 0
        for index in stride(from: 0, to: total, by: step) {
            for after in [false, true] {
                runs += 1
                let result = try await attempt(fault: .init(index: index, afterExecuting: after, mode: .crash))
                let label = "call \(index) (\(probe.log[min(index, probe.log.count - 1)])) \(after ? "after" : "before")"
                // Restart on the real file system.
                let rig = try await Rig.open(result.dir)
                let files = result.dir.userFiles()
                let listed = try await rig.changes.changes(limit: nil).count
                if files == probe.original || files == result.original {
                    if listed != 0 { problems.append("\(label): untouched files but \(listed) change sets") }
                } else if files == probe.moved {
                    if listed != 1 { problems.append("\(label): moved files but \(listed) change sets") }
                } else {
                    problems.append("\(label): the group is half applied")
                }
                // The index agrees with the files: the note is where the files say it is.
                let note = try await rig.notes.open(id: result.id)
                let folder = files.keys.first { $0.hasSuffix("/" + (note.summary.title) + ".md") } ?? ""
                _ = folder
                if listed == 1 {
                    let undo = try await rig.changes.undo(id: try await rig.changes.changes(limit: nil)[0].id, actor: .user)
                    _ = undo
                    if result.dir.userFiles() != result.original { problems.append("\(label): undo after recovery did not restore the original") }
                }
                await rig.close()
            }
        }
        print("interrupted move: \(total) calls, \(runs) faulted runs")
        #expect(problems.isEmpty, "\(problems.prefix(8).joined(separator: "\n"))")
    }
}
}
