import Foundation
import Testing
@testable import MarginCore

// The long-running change-set tests (fault sweeps, stress) are nested in `PerfSuites`: that parent is
// `.serialized`, so they never run at the same time as a timing test and cannot distort its budget.

/// The real file system without the durability flushes. A simulated crash (`FaultInjectingFileSystem`)
/// does not need fsync to be observable, and the sweeps make thousands of writes.
struct NoSyncFileSystem: FileSystem {
    let base: any FileSystem = POSIXFileSystem(durability: .ordinary)
    func attributes(at url: URL) throws -> FileAttributes? { try base.attributes(at: url) }
    func realPath(_ url: URL) throws -> URL { try base.realPath(url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }
    func createDirectories(at url: URL) throws { try base.createDirectories(at: url) }
    func createFile(at url: URL, data: Data, permissions: UInt16?) throws { try base.createFile(at: url, data: data, permissions: permissions) }
    func sync(fileAt url: URL) throws {}
    func syncDirectory(at url: URL) throws {}
    func replaceItem(at destination: URL, withItemAt source: URL) throws { try base.replaceItem(at: destination, withItemAt: source) }
    func moveItemNoReplace(from source: URL, to destination: URL) throws { try base.moveItemNoReplace(from: source, to: destination) }
    func removeFile(at url: URL) throws { try base.removeFile(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [DirectoryEntry] { try base.contentsOfDirectory(at: url) }
}

/// Wraps a real file system and runs a closure just BEFORE chosen calls (by index since `arm`),
/// to simulate another program writing at an exact moment of the store's work.
final class HookFileSystem: FileSystem, @unchecked Sendable {
    private let base: any FileSystem
    private let lock = NSLock()
    private var counter = 0
    private var hooks: [Int: @Sendable () -> Void] = [:]
    private var calls: [String] = []

    init(base: any FileSystem = POSIXFileSystem(durability: .ordinary)) { self.base = base }

    /// `name:lastPathComponent` of every call since `arm`.
    var log: [String] { lock.withLock { calls } }

    func arm(_ hooks: [Int: @Sendable () -> Void]) {
        lock.withLock { self.hooks = hooks; counter = 0; calls = [] }
    }

    private func step<T>(_ name: String, _ url: URL, _ body: () throws -> T) throws -> T {
        let hook: (@Sendable () -> Void)? = lock.withLock {
            calls.append("\(name):\(url.lastPathComponent)")
            defer { counter += 1 }
            return hooks[counter]
        }
        hook?()
        return try body()
    }

    func attributes(at url: URL) throws -> FileAttributes? { try step("attributes", url) { try base.attributes(at: url) } }
    func realPath(_ url: URL) throws -> URL { try step("realPath", url) { try base.realPath(url) } }
    func readData(at url: URL) throws -> Data { try step("readData", url) { try base.readData(at: url) } }
    func createDirectories(at url: URL) throws { try step("createDirectories", url) { try base.createDirectories(at: url) } }
    func createFile(at url: URL, data: Data, permissions: UInt16?) throws {
        try step("createFile", url) { try base.createFile(at: url, data: data, permissions: permissions) }
    }
    func sync(fileAt url: URL) throws { try step("sync", url) { try base.sync(fileAt: url) } }
    func syncDirectory(at url: URL) throws { try step("syncDirectory", url) { try base.syncDirectory(at: url) } }
    func replaceItem(at destination: URL, withItemAt source: URL) throws {
        try step("replaceItem", destination) { try base.replaceItem(at: destination, withItemAt: source) }
    }
    func moveItemNoReplace(from source: URL, to destination: URL) throws {
        try step("moveItemNoReplace", destination) { try base.moveItemNoReplace(from: source, to: destination) }
    }
    func removeFile(at url: URL) throws { try step("removeFile", url) { try base.removeFile(at: url) } }
    func contentsOfDirectory(at url: URL) throws -> [DirectoryEntry] {
        try step("contentsOfDirectory", url) { try base.contentsOfDirectory(at: url) }
    }
}

extension TempDir {
    /// Regular files outside `.margin/` (the user's files), as relative path -> bytes.
    func userFiles() -> [String: Data] {
        snapshot().filter { !$0.key.hasPrefix(".margin/") && !VaultStore.isTemporaryName(String($0.key.split(separator: "/").last ?? "")) }
    }

    /// Names in `.margin/changesets/`.
    func journalFiles() -> [String] {
        snapshot().keys.filter { $0.hasPrefix(".margin/changesets/") }.map { String($0.dropFirst(".margin/changesets/".count)) }.sorted()
    }
}

/// Bytes a lossy code path would damage: BOM, CRLF, non-ASCII, a lone CR, invalid UTF-8.
func nastyBytes(_ tag: String) -> Data {
    var d = Data([0xEF, 0xBB, 0xBF])
    d.append(Data("---\r\nid: \(tag)\r\n---\r\n# Příliš žluťoučký kůň 🧬 \(tag)\r\nline with lone CR\rend\r\n".utf8))
    d.append(Data([0xFF, 0xFE, 0x00, 0x80]))       // not valid UTF-8
    d.append(Data("\r\n- [ ] task ^t-\(tag)\r\n".utf8))
    return d
}

/// Opens a store and journal over `dir`.
func openJournal(_ dir: TempDir, fileSystem: any FileSystem = POSIXFileSystem(durability: .ordinary), clock: any Clock = FixedClock(),
                 retention: ChangeSetRetention = .standard) async throws -> (store: VaultStore, journal: ChangeSetJournal) {
    let store = try await VaultStore.open(root: dir.url, fileSystem: fileSystem, clock: clock, trash: PortableTrash(), createIfMissing: true)
    let journal = try await ChangeSetJournal.open(store: store, clock: clock, retention: retention)
    return (store, journal)
}
