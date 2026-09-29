import Foundation
import Testing
@testable import MarginCore

@Suite struct VaultStoreTests {
    let dir = TempDir()
    let clock = FixedClock()

    /// Tests run with `.ordinary` for speed; the app must keep flushing to the medium.
    @Test func theRealFileSystemFlushesFullyByDefault() {
        #expect(POSIXFileSystem().durability == .full)
    }

    func open(createIfMissing: Bool = false) async throws -> VaultStore {
        try await VaultStore.open(root: dir.url, clock: clock, trash: PortableTrash(), createIfMissing: createIfMissing)
    }

    // MARK: open

    @Test func openRequiresExistingFolder() async throws {
        let missing = dir.file("nope")
        await #expect(throws: MarginError.self) { try await VaultStore.open(root: missing, trash: PortableTrash()) }
        let created = try await VaultStore.open(root: missing, trash: PortableTrash(), createIfMissing: true)
        #expect(created.root.lastPathComponent == "nope")
        try dir.seed("plain.txt", Data("x".utf8))
        await #expect(throws: MarginError.self) { try await VaultStore.open(root: dir.file("plain.txt"), trash: PortableTrash()) }
    }

    // MARK: read / write

    @Test func writeThenReadRoundTripsBytesExactly() async throws {
        let store = try await open()
        let content = String(decoding: trickyBytes(), as: UTF8.self)
        let path = vp("Fall 2026/Cell Biology/Lecture 8 — Cell membrane.md")
        let v = try await store.write(path, content: content)
        let read = try await store.read(path)
        #expect(read.content == content)
        #expect(read.version == v)
        #expect(dir.bytes(path.rawValue) == trickyBytes())
        #expect(v == ContentHash(of: trickyBytes()))
        let raw = try await store.readData(path)
        #expect(raw.data == trickyBytes())
    }

    @Test func readErrors() async throws {
        let store = try await open()
        do { _ = try await store.read(vp("missing.md")); Issue.record("must fail") } catch let e as MarginError { #expect(e.code == "notFound") }
        try dir.seed("folder/x.md", Data("x".utf8))
        await #expect(throws: MarginError.self) { try await store.read(vp("folder")) }
        try dir.seed("binary.md", Data([0xff, 0xfe, 0x00, 0x80]))
        await #expect(throws: MarginError.self) { try await store.read(vp("binary.md")) }
        // The raw bytes are still readable and untouched.
        #expect(try await store.readData(vp("binary.md")).data == Data([0xff, 0xfe, 0x00, 0x80]))
    }

    @Test func conflictWhenVersionDiffers() async throws {
        let store = try await open()
        let p = vp("n.md")
        let v1 = try await store.write(p, content: "one")
        let v2 = try await store.write(p, content: "two", expectedVersion: v1)
        #expect(v2 != v1)
        do {
            try await store.write(p, content: "three", expectedVersion: v1)
            Issue.record("stale write must fail")
        } catch let e as MarginError {
            #expect(e.code == "conflict")
        }
        #expect(dir.bytes("n.md") == Data("two".utf8))
        #expect(try await store.write(p, content: "three", expectedVersion: v2) == ContentHash(of: "three"))
    }

    @Test func externalChangeIsDetected() async throws {
        let store = try await open()
        let p = vp("n.md")
        let v1 = try await store.write(p, content: "mine")
        try dir.seed("n.md", Data("edited elsewhere".utf8))
        await #expect(throws: MarginError.self) { try await store.write(p, content: "overwrite", expectedVersion: v1) }
        #expect(dir.bytes("n.md") == Data("edited elsewhere".utf8))
    }

    @Test func expectedVersionOnMissingFileConflicts() async throws {
        let store = try await open()
        do {
            try await store.write(vp("gone.md"), content: "x", expectedVersion: ContentHash(of: "y"))
            Issue.record("must fail")
        } catch let e as MarginError { #expect(e.code == "conflict") }
        #expect(!dir.exists("gone.md"))
    }

    @Test func writeWithoutVersionCreatesFoldersAndOverwrites() async throws {
        let store = try await open()
        try await store.write(vp("a/b/c.md"), content: "1")
        try await store.write(vp("a/b/c.md"), content: "2")
        #expect(dir.bytes("a/b/c.md") == Data("2".utf8))
        #expect(dir.temporaryFiles.isEmpty)
    }

    @Test func writeRefusesFoldersAndFilesInTheWay() async throws {
        let store = try await open()
        try dir.seed("folder/x.md", Data("x".utf8))
        await #expect(throws: MarginError.self) { try await store.write(vp("folder"), content: "boom") }
        try dir.seed("file.md", Data("f".utf8))
        await #expect(throws: MarginError.self) { try await store.write(vp("file.md/child.md"), content: "boom") }
        #expect(dir.bytes("file.md") == Data("f".utf8))
        #expect(dir.temporaryFiles.isEmpty)
    }

    @Test func overwritePreservesPermissions() async throws {
        let store = try await open()
        try dir.seed("private.md", Data("secret".utf8), permissions: 0o600)
        try dir.seed("shared.md", Data("shared".utf8), permissions: 0o664)
        try dir.seed("script.md", Data("x".utf8), permissions: 0o755)
        for name in ["private.md", "shared.md", "script.md"] {
            let before = try FileManager.default.attributesOfItem(atPath: dir.file(name).path)[.posixPermissions] as? Int
            try await store.write(vp(name), content: "new")
            let after = try FileManager.default.attributesOfItem(atPath: dir.file(name).path)[.posixPermissions] as? Int
            #expect(after == before, "\(name)")
            #expect(dir.bytes(name) == Data("new".utf8))
        }
    }

    // MARK: create

    @Test func createFailsWhenExists() async throws {
        let store = try await open()
        try await store.create(vp("new/note.md"), content: "first")
        do {
            try await store.create(vp("new/note.md"), content: "second")
            Issue.record("must fail")
        } catch let e as MarginError { #expect(e.code == "conflict") }
        #expect(dir.bytes("new/note.md") == Data("first".utf8))
        #expect(dir.temporaryFiles.isEmpty)
        try dir.seed("dir/x.md", Data("x".utf8))
        await #expect(throws: MarginError.self) { try await store.create(vp("dir"), content: "x") }
    }

    // MARK: rename

    @Test func renameMovesAndCreatesFolders() async throws {
        let store = try await open()
        try dir.seed("a/old.md", trickyBytes())
        try await store.rename(vp("a/old.md"), to: vp("b/c/new.md"))
        #expect(!dir.exists("a/old.md"))
        #expect(dir.bytes("b/c/new.md") == trickyBytes())
        #expect(await store.exists(vp("b/c/new.md")))
        #expect(!(await store.exists(vp("a/old.md"))))
    }

    @Test func renameNeverOverwrites() async throws {
        let store = try await open()
        try dir.seed("a.md", Data("A".utf8))
        try dir.seed("b.md", Data("B".utf8))
        do {
            try await store.rename(vp("a.md"), to: vp("b.md"))
            Issue.record("must fail")
        } catch let e as MarginError { #expect(e.code == "conflict") }
        #expect(dir.bytes("a.md") == Data("A".utf8))
        #expect(dir.bytes("b.md") == Data("B".utf8))
        await #expect(throws: MarginError.self) { try await store.rename(vp("nope.md"), to: vp("x.md")) }
        try await store.rename(vp("a.md"), to: vp("a.md"))
        #expect(dir.bytes("a.md") == Data("A".utf8))
    }

    @Test func renameFolderAndRefuseMoveIntoItself() async throws {
        let store = try await open()
        try dir.seed("Course/n.md", Data("n".utf8))
        try dir.seed("Other/empty-target-blocker.md", Data("x".utf8))
        await #expect(throws: MarginError.self) { try await store.rename(vp("Course"), to: vp("Course/sub")) }
        await #expect(throws: MarginError.self) { try await store.rename(vp("Course"), to: vp("Other")) }
        try await store.rename(vp("Course"), to: vp("Renamed"))
        #expect(dir.bytes("Renamed/n.md") == Data("n".utf8))
        #expect(dir.bytes("Other/empty-target-blocker.md") == Data("x".utf8))
    }

    @Test func renameObserverRunsAfterMoveAndMayUseTheStore() async throws {
        actor Recorder: RenameObserver {
            var events: [String] = []
            func vaultDidRename(from: VaultPath, to: VaultPath, isDirectory: Bool, in store: VaultStore) async {
                let movedExists = await store.exists(to)
                events.append("\(from)->\(to) dir=\(isDirectory) targetExists=\(movedExists)")
                // Simulates link rewriting: read-modify-write another note with the version.
                if let other = try? await store.read(vp("linker.md")) {
                    _ = try? await store.write(vp("linker.md"), content: other.content.replacingOccurrences(of: "[[Old]]", with: "[[New]]"), expectedVersion: other.version)
                }
            }
            func snapshot() -> [String] { events }
        }
        let store = try await open()
        let rec = Recorder()
        await store.addRenameObserver(rec)
        try dir.seed("Old.md", Data("x".utf8))
        try dir.seed("linker.md", Data("see [[Old]]".utf8))
        try await store.rename(vp("Old.md"), to: vp("New.md"))
        #expect(await rec.snapshot() == ["Old.md->New.md dir=false targetExists=true"])
        #expect(dir.bytes("linker.md") == Data("see [[New]]".utf8))
        // A failed rename must not notify.
        try? await store.rename(vp("missing.md"), to: vp("x.md"))
        #expect(await rec.snapshot().count == 1)
    }

    // MARK: trash

    @Test func trashMovesInsteadOfDeleting() async throws {
        let store = try await open()
        try dir.seed("Course/Gone.md", trickyBytes())
        let dest = try await store.trash(vp("Course/Gone.md"))
        #expect(!dir.exists("Course/Gone.md"))
        // FixedClock: 2026-09-28 13:24 Europe/Prague = 11:24 UTC.
        #expect(dest?.lastPathComponent == "20260928T112400Z-Gone.md")
        #expect(dir.bytes(".margin/trash/20260928T112400Z-Gone.md") == trickyBytes())
        #expect(dir.temporaryFiles.isEmpty)
    }

    @Test func trashSameNameTwiceKeepsBoth() async throws {
        let store = try await open()
        try dir.seed("a/N.md", Data("first".utf8))
        try dir.seed("b/N.md", Data("second".utf8))
        try await store.trash(vp("a/N.md"))
        try await store.trash(vp("b/N.md"))
        let trashed = dir.snapshot().filter { $0.key.hasPrefix(".margin/trash/") }
        #expect(trashed.count == 2)
        #expect(Set(trashed.values) == [Data("first".utf8), Data("second".utf8)])
    }

    @Test func trashFolderAndErrors() async throws {
        let store = try await open()
        try dir.seed("Old Course/n.md", Data("n".utf8))
        try await store.trash(vp("Old Course"))
        #expect(dir.bytes(".margin/trash/20260928T112400Z-Old Course/n.md") == Data("n".utf8))
        await #expect(throws: MarginError.self) { try await store.trash(vp("missing.md")) }
        await #expect(throws: MarginError.self) { try await store.trash(vp(".margin")) }
        await #expect(throws: MarginError.self) { try await store.trash(vp(".margin/trash/20260928T112400Z-Old Course")) }
        #expect(dir.exists(".margin/trash/20260928T112400Z-Old Course/n.md"))
    }

    @Test func trashTimestampUsesTheClock() async throws {
        let later = FixedClock(now: clock.now.addingTimeInterval(3600 * 24 + 61))
        let store = try await VaultStore.open(root: dir.url, clock: later, trash: PortableTrash())
        try dir.seed("t.md", Data("t".utf8))
        try await store.trash(vp("t.md"))
        #expect(dir.exists(".margin/trash/20260929T112501Z-t.md"))
    }

    // MARK: list / exists

    @Test func listReturnsMarkdownOnlySkippingHidden() async throws {
        let store = try await open()
        for f in ["top.md", "Fall/Bio/Lecture.md", "Fall/Bio/_course.md", "Fall/Bio/_files/pic.png", "Fall/Bio/_files/notes.txt",
                  ".margin/audit.md", ".margin/trash/1-x.md", ".obsidian/x.md", ".hidden.md", "Fall/.secret/n.md", "UPPER.MD", "x.markdown"] {
            try dir.seed(f, Data("x".utf8))
        }
        try dir.seed(".\(UUID().uuidString).margin-tmp", Data("tmp".utf8))
        let all = try await store.list().map(\.rawValue)
        #expect(all == ["Fall/Bio/Lecture.md", "Fall/Bio/_course.md", "UPPER.MD", "top.md"])
        #expect(try await store.list(under: vp("Fall")).map(\.rawValue) == ["Fall/Bio/Lecture.md", "Fall/Bio/_course.md"])
        #expect(try await store.list(under: vp(".margin")).isEmpty)
        await #expect(throws: MarginError.self) { try await store.list(under: vp("nope")) }
        await #expect(throws: MarginError.self) { try await store.list(under: vp("top.md")) }
    }

    @Test func existsCoversFilesAndFolders() async throws {
        let store = try await open()
        try dir.seed("f/n.md", Data("x".utf8))
        #expect(await store.exists(vp("f")))
        #expect(await store.exists(vp("f/n.md")))
        #expect(!(await store.exists(vp("f/other.md"))))
        #expect(!(await store.exists(vp("n.md/x"))))
    }

    // MARK: symlinks

    @Test func symlinksCannotEscapeTheVault() async throws {
        let outside = TempDir()
        try outside.seed("secret.md", Data("outside".utf8))
        let store = try await open()
        try FileManager.default.createSymbolicLink(at: dir.file("escape"), withDestinationURL: outside.url)
        try FileManager.default.createSymbolicLink(at: dir.file("leak.md"), withDestinationURL: outside.file("secret.md"))
        try dir.seed("real.md", Data("in".utf8))
        try FileManager.default.createSymbolicLink(at: dir.file("alias.md"), withDestinationURL: dir.file("real.md"))

        await #expect(throws: MarginError.self) { try await store.write(vp("escape/x.md"), content: "boom") }
        await #expect(throws: MarginError.self) { try await store.read(vp("escape/secret.md")) }
        await #expect(throws: MarginError.self) { try await store.read(vp("leak.md")) }
        await #expect(throws: MarginError.self) { try await store.rename(vp("real.md"), to: vp("escape/moved.md")) }
        #expect(outside.snapshot().keys.sorted() == ["secret.md"])
        #expect(outside.bytes("secret.md") == Data("outside".utf8))
        // A symlink inside the vault to a vault file is readable, but never written through/replaced.
        #expect(try await store.read(vp("alias.md")).content == "in")
        await #expect(throws: MarginError.self) { try await store.write(vp("alias.md"), content: "x") }
        #expect(dir.bytes("real.md") == Data("in".utf8))
        #expect(try await store.list().map(\.rawValue) == ["real.md"])
    }

    // MARK: concurrency

    @Test func hundredConcurrentWritesToDifferentFilesAllLand() async throws {
        let store = try await open()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let path = try VaultPath("Course \(i % 7)/Note \(i).md")
                    try await store.write(path, content: "content \(i)\n" + String(repeating: "line \(i)\n", count: 200))
                }
            }
            try await group.waitForAll()
        }
        let listed = try await store.list()
        #expect(listed.count == 100)
        for i in 0..<100 {
            let read = try await store.read(vp("Course \(i % 7)/Note \(i).md"))
            #expect(read.content == "content \(i)\n" + String(repeating: "line \(i)\n", count: 200))
        }
        #expect(dir.temporaryFiles.isEmpty)
    }

    @Test func concurrentWritesWithSameVersionExactlyOneWins() async throws {
        let store = try await open()
        let p = vp("shared.md")
        let v0 = try await store.write(p, content: "base")
        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for i in 0..<50 {
                group.addTask { (try? await store.write(p, content: "writer \(i)", expectedVersion: v0)) != nil }
            }
            var out: [Bool] = []
            for await r in group { out.append(r) }
            return out
        }
        #expect(results.filter { $0 }.count == 1)
        let final = try await store.read(p).content
        #expect(final.hasPrefix("writer "))
    }

    @Test func concurrentReadsSeeWholeFilesDuringOverwrites() async throws {
        let store = try await open()
        let p = vp("busy.md")
        let a = String(repeating: "A", count: 100_000), b = String(repeating: "B", count: 100_000)
        try await store.write(p, content: a)
        let url = dir.file("busy.md")
        // Reads that bypass the actor, as an external process (Obsidian, Finder) would.
        let reader = Task.detached { () -> Int in
            var torn = 0
            for _ in 0..<300 {
                let d = FileManager.default.contents(atPath: url.path) ?? Data()
                if d != Data(a.utf8) && d != Data(b.utf8) { torn += 1 }
            }
            return torn
        }
        for i in 0..<100 { try await store.write(p, content: i.isMultiple(of: 2) ? b : a) }
        #expect(await reader.value == 0)
    }

    // MARK: recovery on open

    @Test func openRemovesLeftoverTemporariesOnly() async throws {
        let leftovers = [".\(UUID().uuidString).margin-tmp", "Fall/Bio/.\(UUID().uuidString).margin-tmp", ".margin/.\(UUID().uuidString).margin-tmp"]
        for l in leftovers { try dir.seed(l, Data("partial".utf8)) }
        // Look-alikes that are not ours must survive.
        let keep = [".notes.margin-tmp", "x.margin-tmp", ".\(UUID().uuidString).margin-tmp.md", ".git/.\(UUID().uuidString).margin-tmp",
                    ".margin/trash/.\(UUID().uuidString).margin-tmp", "real.md"]
        for k in keep { try dir.seed(k, Data("keep".utf8)) }
        let store = try await open()
        #expect(await store.recoveredTemporaryFiles.map(\.rawValue) == leftovers.sorted())
        for l in leftovers { #expect(!dir.exists(l)) }
        for k in keep { #expect(dir.bytes(k) == Data("keep".utf8), "\(k)") }
        let second = try await open()
        #expect(await second.recoveredTemporaryFiles.isEmpty)
    }
}
