import Foundation
import Testing
@testable import MarginCore

extension Robustness {
/// M12-03 at the store level: the rules the services above rely on.
@Suite struct StoreRobustnessTests {
    private func open(_ d: TempDir, _ fs: any FileSystem = POSIXFileSystem()) async throws -> VaultStore {
        try await VaultStore.open(root: d.url, fileSystem: fs, clock: FixedClock(), trash: PortableTrash())
    }

    @Test func aWriteToAMissingVaultFailsAndCreatesNothing() async throws {
        let d = TempDir()
        try d.seed("A/n.md", Data("x".utf8))
        let store = try await open(d)
        #expect(await store.isAvailable())
        let away = d.url.appendingPathExtension("away")
        try FileManager.default.moveItem(at: d.url, to: away)
        defer { try? FileManager.default.removeItem(at: away); try? FileManager.default.moveItem(at: away, to: d.url) }
        #expect(!(await store.isAvailable()))
        for body in [
            { _ = try await store.write(vp("A/n.md"), content: "new") },
            { _ = try await store.write(vp("B/new.md"), content: "new") },
            { _ = try await store.create(vp("C/created.md"), content: "new") },
            { try await store.createFolder(vp("E/F")) },
            { try await store.rename(vp("A/n.md"), to: vp("D/n.md")) },
            { _ = try await store.trash(vp("A/n.md")) },
            { _ = try await store.read(vp("A/n.md")) },
            { _ = try await store.list() },
        ] as [@Sendable () async throws -> Void] {
            let code = await robustCode { try await body() }
            #expect(code == "notFound", "\(code ?? "succeeded")")
        }
        #expect(!FileManager.default.fileExists(atPath: d.url.path))
    }

    @Test func aReadOnlyFileIsRefusedWithReadOnlyButStillReadable() async throws {
        let d = TempDir()
        try d.seed("n.md", Data("original".utf8), permissions: 0o444)
        let store = try await open(d)
        #expect(await robustCode { try await store.write(vp("n.md"), content: "new") } == "readOnly")
        #expect(await robustCode { try await store.writeData(vp("n.md"), data: Data("new".utf8), expectedVersion: ContentHash(of: Data("original".utf8))) } == "readOnly")
        // A stale version is still a conflict first: the caller has to re-read either way.
        #expect(await robustCode { try await store.write(vp("n.md"), content: "new", expectedVersion: ContentHash(of: Data("stale".utf8))) } == "conflict")
        #expect(try await store.read(vp("n.md")).content == "original")
        #expect(d.bytes("n.md") == Data("original".utf8))
        #expect(d.temporaryFiles.isEmpty)
        try d.setPermissions(0o644, "n.md")
        _ = try await store.write(vp("n.md"), content: "new")
        #expect(d.bytes("n.md") == Data("new".utf8))
    }

    @Test func listSkipsAnUnreadableSubfolderButNotAnUnreadableStartingPoint() async throws {
        let d = TempDir()
        try d.seed("Open/a.md", Data("a".utf8))
        try d.seed("Locked/b.md", Data("b".utf8))
        try d.seed("Open/Inner/c.md", Data("c".utf8))
        let fs = ScriptedFileSystem()
        fs.inject(.denied, ops: ["contentsOfDirectory"], pathContains: "Locked")
        let store = try await open(d, fs)
        #expect(try await store.list().map(\.rawValue) == ["Open/Inner/c.md", "Open/a.md"])
        #expect(try await store.list(under: vp("Open")).map(\.rawValue) == ["Open/Inner/c.md", "Open/a.md"])
        #expect(await robustCode { try await store.list(under: vp("Locked")) } == "io")
        // Other failures of a subfolder are not swallowed: a dying disk is not a permission problem.
        fs.clear()
        fs.inject(.io, ops: ["contentsOfDirectory"], pathContains: "Locked")
        #expect(await robustCode { try await store.list() } == "io")
        fs.clear()
        #expect(try await store.list().count == 3)
    }

    @Test func permissionDeniedIsRecognisedByItsErrno() {
        #expect(FileSystemError.failed("opendir x: Permission denied (errno 13)").isPermissionDenied)
        #expect(FileSystemError.failed("rename x: Operation not permitted (errno 1)").isPermissionDenied)
        #expect(!FileSystemError.failed("write x: No space left on device (errno 28)").isPermissionDenied)
        #expect(!FileSystemError.notFound("x").isPermissionDenied)
    }

    @Test func aFailedDirectorySyncIsReportedToTheWatcherAsAnOutsideChange() async throws {
        let d = TempDir()
        try d.seed("n.md", Data("old".utf8))
        let fs = ScriptedFileSystem()
        let registry = OwnWriteRegistry(ttl: 60)
        let store = try await VaultStore.open(root: d.url, fileSystem: fs, clock: FixedClock(), trash: PortableTrash(), ownWrites: registry)
        fs.inject(.noSpace, ops: ["syncDirectory"])
        #expect(await robustCode { try await store.write(vp("n.md"), content: "new") } == "io")
        #expect(d.bytes("n.md") == Data("new".utf8))
        // The write is not announced as the app's own: the watcher must report it.
        #expect(await registry.consume(path: "n.md", hash: ContentHash(of: Data("new".utf8)).hex) == false)
    }
}
}
