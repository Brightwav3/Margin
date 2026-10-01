#if os(macOS)
import Foundation
import Testing
@testable import MarginCore

/// The watcher contract of `FileWatcherTests`, against the FSEvents watcher the app uses on macOS.
@Suite struct FSEventsFileWatcherTests {
    private func makeVault() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("margin-fsevents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Course"), withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, _ rel: String, in root: URL) throws {
        try text.write(to: root.appendingPathComponent(rel), atomically: true, encoding: .utf8)
    }

    @Test func createModifyAndDeleteAreReported() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", "Course/old.md", in: root)
        let c = Collector(FSEventsFileWatcher(root: root).changes())
        defer { c.stop() }

        try write("hello", "Course/new.md", in: root)
        #expect(await c.wait { $0.contains(FileChange(path: "Course/new.md", kind: .created)) })
        try write("changed content", "Course/old.md", in: root)
        #expect(await c.wait { $0.contains(FileChange(path: "Course/old.md", kind: .modified)) })
        try FileManager.default.removeItem(at: root.appendingPathComponent("Course/old.md"))
        #expect(await c.wait { $0.contains(FileChange(path: "Course/old.md", kind: .deleted)) })
    }

    @Test func deletingAFileThatWasNeverChangedIsReported() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", "Course/x.md", in: root)
        try await Task.sleep(nanoseconds: 300_000_000)
        let c = Collector(FSEventsFileWatcher(root: root).changes())
        defer { c.stop() }
        try FileManager.default.removeItem(at: root.appendingPathComponent("Course/x.md"))
        #expect(await c.wait(timeout: 5) { $0.contains(FileChange(path: "Course/x.md", kind: .deleted)) })
    }

    @Test func changesAfterAQuietStartAreStillReported() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", "Course/x.md", in: root)
        let c = Collector(FSEventsFileWatcher(root: root).changes())
        defer { c.stop() }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Course/x.md"))
        #expect(await c.wait(timeout: 5) { $0.contains(FileChange(path: "Course/x.md", kind: .deleted)) })
    }

    /// A file the store created must be reported when another program deletes it. The store used
    /// to create files through link(2) + unlink(2), and FSEvents never reports the deletion of
    /// such a file on APFS, so a note removed in Finder stayed in the app.
    @Test func deletingAFileTheStoreCreatedIsReported() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await VaultStore.open(root: root, clock: FixedClock(), trash: PortableTrash())
        try await store.createData(vp("Course/created.md"), data: Data("by the store".utf8))
        let c = Collector(FSEventsFileWatcher(root: root).changes())
        defer { c.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Course/created.md"))
        #expect(await c.wait(timeout: 5) { $0.contains(FileChange(path: "Course/created.md", kind: .deleted)) })
    }

    /// The app writes X, and another program puts the old content back before the watcher looked.
    /// The file ends as the watcher last saw it, but the app believes X: the change must be reported.
    @Test func anOwnWriteRevertedFromOutsideIsReported() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "original"
        try write(original, "Course/n.md", in: root)
        let registry = OwnWriteRegistry(ttl: 60)
        let c = Collector(FSEventsFileWatcher(root: root, latency: 0.3, ownWrites: registry).changes())
        defer { c.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)
        let own = "written by the app"
        await registry.register(path: "Course/n.md", hash: ContentHash(of: own))
        try write(own, "Course/n.md", in: root)
        try write(original, "Course/n.md", in: root)   // within the latency: one batch sees only the end
        #expect(await c.wait(timeout: 5) { $0.contains(FileChange(path: "Course/n.md", kind: .modified)) })
    }

    /// A coalesced batch sees only the last file content, so an older announced app write must not
    /// hide an external write that restores that older version after a newer app write.
    @Test func anOlderOwnWriteHashCannotHideARevertedExternalWrite() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "original"
        try write(original, "Course/n.md", in: root)
        let registry = OwnWriteRegistry(ttl: 60)
        let c = Collector(FSEventsFileWatcher(root: root, latency: 1, ownWrites: registry).changes())
        defer { c.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)

        let earlier = "first app write"
        await registry.register(path: "Course/n.md", hash: ContentHash(of: earlier))
        try write(earlier, "Course/n.md", in: root)
        let latest = "second app write"
        await registry.register(path: "Course/n.md", hash: ContentHash(of: latest))
        try write(latest, "Course/n.md", in: root)
        try write(earlier, "Course/n.md", in: root) // external restore of a superseded app write

        #expect(await c.wait(timeout: 5) { $0.contains(FileChange(path: "Course/n.md", kind: .modified)) })
    }

    /// The store registers a write before making it. A batch that arrives in between sees the file
    /// untouched: that is not an undone write, and the registration must survive for the real write.
    @Test func aRegistrationBeforeTheWriteIsKeptWhenTheFileIsUntouched() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("note", "Course/n.md", in: root)
        let registry = OwnWriteRegistry(ttl: 60)
        let c = Collector(FSEventsFileWatcher(root: root, ownWrites: registry).changes())
        defer { c.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)
        await registry.register(path: "Course/n.md", hash: OwnWriteRegistry.deletedHash)   // announced, not done yet
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Course/sub"), withIntermediateDirectories: true)
        await c.settle()   // the folder event makes the watcher rescan while n.md is still there
        try FileManager.default.removeItem(at: root.appendingPathComponent("Course/n.md"))   // the announced delete
        await c.settle()
        #expect(!c.all.contains { $0.path == "Course/n.md" }, "\(c.all)")
    }

    /// Stopping a watcher while FSEvents is delivering must not touch freed state.
    @Test func stoppingDuringABurstOfEventsIsSafe() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Task.detached {
            var i = 0
            while !Task.isCancelled {
                try? "x\(i)".write(to: root.appendingPathComponent("Course/burst\(i % 50).md"), atomically: false, encoding: .utf8)
                i += 1
            }
        }
        defer { writer.cancel() }
        for _ in 0..<300 {
            let c = Collector(FSEventsFileWatcher(root: root, latency: 0.001).changes())
            try await Task.sleep(nanoseconds: UInt64.random(in: 0...5_000_000))
            c.stop()
        }
    }

    /// A rename in Finder: the old path goes, the new one comes.
    @Test func aRenamedFileIsReportedAsDeletedAndCreated() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", "Course/old.md", in: root)
        let c = Collector(FSEventsFileWatcher(root: root).changes())
        defer { c.stop() }
        try FileManager.default.moveItem(at: root.appendingPathComponent("Course/old.md"), to: root.appendingPathComponent("Course/new.md"))
        #expect(await c.wait(timeout: 5) {
            $0.contains(FileChange(path: "Course/old.md", kind: .deleted)) && $0.contains(FileChange(path: "Course/new.md", kind: .created))
        })
    }

    /// Moving a whole course folder reports every note at its new place and gone from the old one.
    @Test func aMovedFolderReportsItsFilesAtTheNewPlace() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", "Course/x.md", in: root)
        try write("b", "Course/y.md", in: root)
        let c = Collector(FSEventsFileWatcher(root: root).changes())
        defer { c.stop() }
        try FileManager.default.moveItem(at: root.appendingPathComponent("Course"), to: root.appendingPathComponent("Moved"))
        #expect(await c.wait(timeout: 5) { changes in
            ["x", "y"].allSatisfy { n in
                changes.contains(FileChange(path: "Course/\(n).md", kind: .deleted)) && changes.contains(FileChange(path: "Moved/\(n).md", kind: .created))
            }
        })
    }

    @Test func aDeletedFolderReportsItsFiles() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", "Course/x.md", in: root)
        let c = Collector(FSEventsFileWatcher(root: root).changes())
        defer { c.stop() }
        try FileManager.default.removeItem(at: root.appendingPathComponent("Course"))
        #expect(await c.wait(timeout: 5) { $0.contains(FileChange(path: "Course/x.md", kind: .deleted)) })
    }
}
#endif
