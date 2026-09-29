import Foundation
import Testing
@testable import MarginCore

/// The real file system, except that nothing can be written below `.margin/history/`.
private struct HistoryBlockedFileSystem: FileSystem {
    let base: any FileSystem = NoSyncFileSystem()
    private func check(_ url: URL) throws {
        if url.path.contains("/history/") { throw FileSystemError.failed("history is not writable (test)") }
    }
    func attributes(at url: URL) throws -> FileAttributes? { try base.attributes(at: url) }
    func realPath(_ url: URL) throws -> URL { try base.realPath(url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }
    func createDirectories(at url: URL) throws { try check(url); try base.createDirectories(at: url) }
    func createFile(at url: URL, data: Data, permissions: UInt16?) throws {
        try check(url); try base.createFile(at: url, data: data, permissions: permissions)
    }
    func sync(fileAt url: URL) throws { try base.sync(fileAt: url) }
    func syncDirectory(at url: URL) throws { try base.syncDirectory(at: url) }
    func replaceItem(at destination: URL, withItemAt source: URL) throws {
        try check(destination); try base.replaceItem(at: destination, withItemAt: source)
    }
    func moveItemNoReplace(from source: URL, to destination: URL) throws {
        try check(destination); try base.moveItemNoReplace(from: source, to: destination)
    }
    func removeFile(at url: URL) throws { try base.removeFile(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [DirectoryEntry] { try base.contentsOfDirectory(at: url) }
}

/// Storage that refuses every write.
private struct FailingStorage: HistoryStorage {
    func names(note: NoteID) async throws -> [String] { [] }
    func read(note: NoteID, name: String) async throws -> Data { throw MarginError.io("read failed") }
    func write(note: NoteID, name: String, data: Data) async throws { throw MarginError.io("write failed") }
    func remove(note: NoteID, name: String) async throws {}
}

private struct NoHost: HistoryHost {
    func current(note: NoteID) async throws -> Note { throw MarginError.invalid("no host") }
    func save(note: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet { throw MarginError.invalid("no host") }
}

@Suite struct AutoSnapshotTests {
    @Test func aFailingSnapshotDoesNotThrowFromTheEngine() async {
        let engine = HistoryEngine(storage: FailingStorage(), host: NoHost(), clock: FixedClock())
        await engine.autoSnapshot(note: "bio/lecture-9", text: "# Text\n")
        #expect((try? await engine.versions(note: "bio/lecture-9"))?.isEmpty == true)
    }

    @Test func aSaveSucceedsWhenTheSnapshotCannotBeWritten() async throws {
        let dir = TempDir()
        let store = try await VaultStore.open(root: dir.url, trash: PortableTrash(), createIfMissing: true)
        try await SampleVaultGenerator.generate(into: store, from: Fixtures.week5)
        let backend = try await VaultBackend.open(at: dir.url, clock: FixedClock(), watchInterval: 0.05,
                                                  fileSystem: HistoryBlockedFileSystem(), trash: PortableTrash())
        let notes = VaultNoteRepository(backend: backend)
        let current = try await notes.open(id: "bio/lecture-9")
        let changes = try await notes.save(id: "bio/lecture-9", text: "# Saved anyway\n", actor: .user,
                                           baseVersion: current.version, dryRun: false, idempotencyKey: nil)
        #expect(changes.entries.count == 1)
        #expect(try await notes.open(id: "bio/lecture-9").text == "# Saved anyway\n")
        #expect(try await VaultHistoryService(backend: backend).versions(note: "bio/lecture-9").isEmpty)
        await backend.shutdown()
    }
}
