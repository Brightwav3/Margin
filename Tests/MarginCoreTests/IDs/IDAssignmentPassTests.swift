import Foundation
import Testing
@testable import MarginCore

@Suite struct IDAssignmentPassTests {
    let dir = TempDir()

    func open(ownWrites: OwnWriteRegistry? = nil) async throws -> VaultStore {
        try await VaultStore.open(root: dir.url, clock: FixedClock(), trash: PortableTrash(), ownWrites: ownWrites)
    }

    func seedVault() throws {
        try dir.seed("fall-2026/bio/Cell Biology.md", Data("---\ntype: lecture\n---\n# Cell Biology\n\n- [ ] Read chapter 2 @2026-10-01\n- [x] Watch video\n".utf8))
        try dir.seed("fall-2026/bio/Glossary.md", Data("# Glossary\r\n\r\n- [ ] Learn terms  \r\n".utf8))
        try dir.seed("fall-2026/chem/Atoms.md", Data("\u{FEFF}Atoms\n\n- [ ] Balance equations\n    - [ ] Redox\n".utf8))
        try dir.seed("Inbox/Loose.md", Data("Just text, no tasks.\n".utf8))
    }

    func pass(_ store: VaultStore, seed: UInt64 = 1) -> IDAssignmentPass {
        IDAssignmentPass(store: store, generator: makeGenerator(seed))
    }

    func index(_ store: VaultStore) async throws -> NoteIndex {
        let idx = NoteIndex(clock: FixedClock())
        var entries: [(path: String, content: String)] = []
        for p in try await store.list() { entries.append((p.rawValue, try await store.read(p).content)) }
        await idx.build(entries: entries)
        return idx
    }

    @Test func assignsNoteAndTaskIDsAcrossTheVault() async throws {
        try seedVault()
        let store = try await open()
        let report = try await pass(store).run()
        #expect(report.scanned == 4)
        #expect(report.notesAssigned == 4)
        #expect(report.tasksAssigned == 5)
        #expect(report.changed.count == 4)
        #expect(report.skipped.isEmpty)
        let idx = try await index(store)
        for n in await idx.allNotes {
            #expect(n.hasStableID, "\(n.path)")
            #expect(n.tasksWithoutID == 0)
            #expect(n.tasks.allSatisfy { !StableIDGenerator.isPlaceholderTaskID($0.id) })
        }
        #expect(await idx.notesNeedingIDs().isEmpty)
    }

    @Test func secondRunChangesNothing() async throws {
        try seedVault()
        let store = try await open()
        let p = pass(store)
        _ = try await p.run()
        let before = dir.snapshot()
        let again = try await p.run()
        #expect(again.isNoop)
        #expect(again.notesAssigned == 0 && again.tasksAssigned == 0 && again.duplicatesReassigned == 0)
        #expect(dir.snapshot() == before)
        // A fresh pass object with another seed is a no-op too.
        let third = try await pass(store, seed: 777).run()
        #expect(third.isNoop)
        #expect(dir.snapshot() == before)
    }

    @Test func fileBytesOtherThanTheInsertedIDsSurvive() async throws {
        try seedVault()
        let store = try await open()
        try dir.seed("fall-2026/bio/_course.md", Data("---\nname: Cell Biology\n---\n- [ ] not a note\n".utf8))
        try dir.seed("fall-2026/bio/notes.txt", Data("- [ ] plain text file\n".utf8))
        try dir.seed(".margin/state.md", Data("- [ ] internal\n".utf8))
        let untouched = ["fall-2026/bio/_course.md", "fall-2026/bio/notes.txt", ".margin/state.md", "Inbox/Loose.md"]
        let before = Dictionary(uniqueKeysWithValues: untouched.map { ($0, dir.bytes($0)) })
        _ = try await pass(store).run()
        for path in untouched.filter({ $0 != "Inbox/Loose.md" }) { #expect(dir.bytes(path) == before[path]!, "\(path)") }
        // CRLF and BOM files keep their style.
        let glossary = String(decoding: dir.bytes("fall-2026/bio/Glossary.md")!, as: UTF8.self)
        #expect(masked(glossary) == "---\r\nid: N\r\n---\r\n# Glossary\r\n\r\n- [ ] Learn terms  ^T\r\n")
        let atoms = dir.bytes("fall-2026/chem/Atoms.md")!
        #expect(Array(atoms.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(stripInserted(String(decoding: atoms, as: UTF8.self).replacing(#/^\u{FEFF}---\nid: n-[0-9a-z]+\n---\n/#, with: "")) == stripInserted("Atoms\n\n- [ ] Balance equations\n    - [ ] Redox\n"))
    }

    @Test func writesUseExpectedVersionAndLeaveNoTemporaryFiles() async throws {
        try seedVault()
        let store = try await open()
        let plan = try await pass(store).plan()
        #expect(plan.edits.count == 4)
        for e in plan.edits {
            #expect(e.version == ContentHash(of: e.result.original))
        }
        // Someone edits a file between planning and writing: the pass must not overwrite it.
        try dir.seed("fall-2026/bio/Glossary.md", Data("# Glossary\nEdited elsewhere\n- [ ] new task\n".utf8))
        let report = await pass(store).apply(plan)
        #expect(report.changed.count == 3)
        #expect(report.skipped.count == 1)
        #expect(report.skipped.first?.path == vp("fall-2026/bio/Glossary.md"))
        #expect(report.skipped.first?.error.code == "conflict")
        #expect(dir.bytes("fall-2026/bio/Glossary.md") == Data("# Glossary\nEdited elsewhere\n- [ ] new task\n".utf8))
        #expect(dir.temporaryFiles.isEmpty)
        // The next run picks the file up.
        let next = try await pass(store).run()
        #expect(next.changed == [vp("fall-2026/bio/Glossary.md")])
    }

    @Test func dryRunReportsButWritesNothing() async throws {
        try seedVault()
        let store = try await open()
        let before = dir.snapshot()
        let report = try await pass(store).run(dryRun: true)
        #expect(report.dryRun)
        #expect(report.changed.count == 4 && report.tasksAssigned == 5 && report.notesAssigned == 4)
        #expect(dir.snapshot() == before)
    }

    @Test func scopeLimitsWhichFilesAreEdited() async throws {
        try seedVault()
        let store = try await open()
        let only = vp("fall-2026/chem/Atoms.md")
        let report = try await pass(store).run(scope: [only])
        #expect(report.changed == [only])
        #expect(dir.bytes("fall-2026/bio/Glossary.md") == Data("# Glossary\r\n\r\n- [ ] Learn terms  \r\n".utf8))
        #expect(!(String(decoding: dir.bytes("fall-2026/chem/Atoms.md")!, as: UTF8.self)).isEmpty)
    }

    @Test func duplicateTaskAndNoteIDsKeepTheFirstByPathAndReassignTheLater() async throws {
        try dir.seed("a/first.md", Data("---\nid: n-same\n---\n- [ ] original ^t-dupe\n- [ ] again ^t-dupe\n".utf8))
        try dir.seed("b/second.md", Data("---\nid: n-same\n---\n- [ ] pasted copy ^t-dupe\n- [ ] unique ^t-uniq\n".utf8))
        let store = try await open()
        let report = try await pass(store).run()
        #expect(report.duplicatesReassigned == 3)   // 2nd task line in first.md, note id and pasted line in second.md
        let first = String(decoding: dir.bytes("a/first.md")!, as: UTF8.self)
        let second = String(decoding: dir.bytes("b/second.md")!, as: UTF8.self)
        #expect(first.hasPrefix("---\nid: n-same\n---\n- [ ] original ^t-dupe\n- [ ] again ^t-"))
        #expect(!first.hasSuffix("again ^t-dupe\n"))
        #expect(!second.contains("id: n-same"))
        #expect(!second.contains("pasted copy ^t-dupe"))
        #expect(second.contains("- [ ] unique ^t-uniq\n"))
        let idx = try await index(store)
        #expect(await idx.duplicateNoteIDs().isEmpty)
        #expect(await idx.duplicateTaskIDs().isEmpty)
        #expect(try await pass(store).run().isNoop)
    }

    @Test func idsSurviveRenameMoveAndEditsThroughTheStore() async throws {
        try seedVault()
        let store = try await open()
        let p = pass(store)
        _ = try await p.run()
        let before = try await index(store)
        let oldNote = try #require(await before.note(byPath: "fall-2026/bio/Cell Biology.md"))
        let oldTasks = oldNote.tasks.map(\.id)

        try await store.rename(vp("fall-2026/bio/Cell Biology.md"), to: vp("fall-2026/bio/Cell Membrane.md"))
        try await store.rename(vp("fall-2026/bio/Cell Membrane.md"), to: vp("fall-2027/bio2/sub/Cell Membrane.md"))
        let path = vp("fall-2027/bio2/sub/Cell Membrane.md")
        var (text, version) = try await store.read(path)
        text = text.replacingOccurrences(of: "Read chapter 2", with: "Read chapter 3 and 4")
        try await store.write(path, content: text, expectedVersion: version)
        (text, version) = try await store.read(path)

        #expect(try await p.run().isNoop)
        let after = try await index(store)
        let moved = try #require(await after.note(byPath: path.rawValue))
        #expect(moved.id == oldNote.id)
        #expect(moved.tasks.map(\.id) == oldTasks)
        #expect(moved.tasks.first?.text == "Read chapter 3 and 4")
        #expect(try await store.read(path).version == version)
    }

    @Test func ownWritesAreRegisteredSoTheWatcherStaysQuiet() async throws {
        try seedVault()
        let registry = OwnWriteRegistry(ttl: 600)
        let store = try await open(ownWrites: registry)
        let report = try await pass(store).run()
        #expect(report.changed.count == 4)
        #expect(await registry.pendingCount == 4)
        for path in report.changed {
            let (_, v) = try await store.read(path)
            #expect(await registry.consume(path: path.rawValue, hash: v))
        }
        #expect(await registry.pendingCount == 0)
        // A no-op run announces nothing.
        _ = try await pass(store).run()
        #expect(await registry.pendingCount == 0)
    }

    @Test func migrationMapsPlaceholderIDsToTheNewOnes() async throws {
        try seedVault()
        let store = try await open()
        let old = try await index(store)
        var oldNoteIDs: [String: String] = [:]
        var oldTaskIDs: [String: [String]] = [:]
        for n in await old.allNotes {
            oldNoteIDs[n.path] = n.id
            oldTaskIDs[n.path] = n.tasks.map(\.id)
        }
        let report = try await pass(store).run()
        let new = try await index(store)
        #expect(report.migrations.filter { $0.kind == .note }.count == 4)
        for m in report.migrations {
            let path = m.path.rawValue
            let note = try #require(await new.note(byPath: path))
            switch m.kind {
            case .note:
                #expect(m.oldID == oldNoteIDs[path])
                #expect(m.newID == note.id)
            case .task:
                #expect(note.tasks.contains { $0.id == m.newID })
                let position = try #require(note.tasks.firstIndex { $0.id == m.newID })
                #expect(m.oldID == oldTaskIDs[path]?[position])
            }
        }
        #expect(report.migrations.filter { $0.kind == .task }.count == 5)
    }

    @Test func unreadableAndUnsafeFilesAreReportedNotTouched() async throws {
        try dir.seed("bad.md", Data([0xff, 0xfe, 0x00, 0x80]))
        try dir.seed("open-fence.md", Data("---\ntype: x\n- [ ] task\n".utf8))
        try dir.seed("ok.md", Data("- [ ] fine\n".utf8))
        let store = try await open()
        let report = try await pass(store).run()
        #expect(dir.bytes("bad.md") == Data([0xff, 0xfe, 0x00, 0x80]))
        #expect(report.skipped.contains { $0.path == vp("bad.md") })
        #expect(report.skipped.contains { $0.path == vp("open-fence.md") })
        // The unsafe note still gets its task id, but no note id and no new frontmatter.
        let fence = String(decoding: dir.bytes("open-fence.md")!, as: UTF8.self)
        #expect(fence.hasPrefix("---\ntype: x\n- [ ] task ^t-"))
        #expect(!fence.contains("id: n-"))
        #expect(String(decoding: dir.bytes("ok.md")!, as: UTF8.self).contains("id: n-"))
    }

    @Test func emptyVaultIsANoop() async throws {
        let store = try await open()
        let report = try await pass(store).run()
        #expect(report.scanned == 0 && report.isNoop)
    }
}
