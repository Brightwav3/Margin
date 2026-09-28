import Foundation
import Testing
@testable import MarginCore

private func makeVault() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("margin-watch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir.appendingPathComponent(".margin"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("Course"), withIntermediateDirectories: true)
    return dir.resolvingSymlinksInPath()
}

private func write(_ text: String, _ rel: String, in root: URL) throws {
    try text.write(to: root.appendingPathComponent(rel), atomically: true, encoding: .utf8)
}

/// Collects batches from a stream in the background.
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [[FileChange]] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<[FileChange]>) {
        task = Task { [self] in
            for await batch in stream {
                append(batch)
            }
        }
    }
    private func append(_ b: [FileChange]) { lock.lock(); items.append(b); lock.unlock() }
    var all: [FileChange] { lock.lock(); defer { lock.unlock() }; return items.flatMap { $0 } }
    var batches: [[FileChange]] { lock.lock(); defer { lock.unlock() }; return items }
    func stop() { task?.cancel() }

    func wait(timeout: TimeInterval = 5, until cond: ([FileChange]) -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond(all) { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return cond(all)
    }
}

private func settle() async { try? await Task.sleep(nanoseconds: 900_000_000) }

@Suite struct FileWatcherTests {
    @Test func detectsCreateModifyDeleteWithinOneSecond() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", "Course/old.md", in: root)
        let c = Collector(PollingFileWatcher(root: root, interval: 0.1).changes())
        defer { c.stop() }

        let t0 = Date()
        try write("hello", "Course/new.md", in: root)
        #expect(await c.wait { $0.contains(FileChange(path: "Course/new.md", kind: .created)) })
        #expect(Date().timeIntervalSince(t0) < 1.0)

        try write("changed content", "Course/old.md", in: root)
        #expect(await c.wait { $0.contains(FileChange(path: "Course/old.md", kind: .modified)) })

        try FileManager.default.removeItem(at: root.appendingPathComponent("Course/old.md"))
        #expect(await c.wait { $0.contains(FileChange(path: "Course/old.md", kind: .deleted)) })
    }

    @Test func renameIsDeletePlusCreate() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", "Course/x.md", in: root)
        let c = Collector(PollingFileWatcher(root: root, interval: 0.1).changes())
        defer { c.stop() }
        try FileManager.default.moveItem(at: root.appendingPathComponent("Course/x.md"),
                                         to: root.appendingPathComponent("Course/y.md"))
        #expect(await c.wait { $0.count >= 2 })
        #expect(Set(c.all) == [FileChange(path: "Course/x.md", kind: .deleted),
                               FileChange(path: "Course/y.md", kind: .created)])
    }

    @Test func ignoresMarginDotfilesAndOtherFiles() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let c = Collector(PollingFileWatcher(root: root, interval: 0.1).changes())
        defer { c.stop() }
        try write("x", ".margin/index.md", in: root)
        try write("x", "Course/.hidden.md", in: root)
        try write("x", "Course/data.txt", in: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Course/_files"), withIntermediateDirectories: true)
        try write("png", "Course/_files/pic.png", in: root)
        try write("x", "Course/real.md", in: root)
        #expect(await c.wait { $0.contains(FileChange(path: "Course/real.md", kind: .created)) })
        await settle()
        #expect(Set(c.all) == [FileChange(path: "Course/real.md", kind: .created),
                               FileChange(path: "Course/_files/pic.png", kind: .created)])
    }

    @Test func ownWriteIsSwallowedOnce() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = OwnWriteRegistry()
        let c = Collector(PollingFileWatcher(root: root, interval: 0.1, ownWrites: registry).changes())
        defer { c.stop() }

        let own = "own content"
        await registry.register(path: "Course/own.md", hash: ContentHash.fnv1a(Data(own.utf8)))
        try write(own, "Course/own.md", in: root)
        try write("external", "Course/ext.md", in: root)
        #expect(await c.wait { $0.contains(FileChange(path: "Course/ext.md", kind: .created)) })
        await settle()
        #expect(!c.all.contains { $0.path == "Course/own.md" })
        #expect(await registry.pendingCount == 0)

        // The registration was consumed: a later identical-hash edit is reported again.
        try write("different", "Course/own.md", in: root)
        #expect(await c.wait { $0.contains { $0.path == "Course/own.md" } })
    }

    @Test func rapidEditsAreCoalesced() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("v0", "Course/r.md", in: root)
        let c = Collector(PollingFileWatcher(root: root, interval: 0.3).changes())
        defer { c.stop() }
        for i in 1...8 { try write("version \(i)", "Course/r.md", in: root) }
        #expect(await c.wait { !$0.isEmpty })
        await settle()
        #expect(c.all == [FileChange(path: "Course/r.md", kind: .modified)])
    }

    @Test func cancellationStopsPolling() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let stream = PollingFileWatcher(root: root, interval: 0.05).changes()
        let done = Task { () -> Bool in
            for await _ in stream {}
            return true
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        done.cancel()
        // Cancelling the consumer terminates the stream; the loop must return promptly.
        let finished = await withTaskGroup(of: Bool.self) { g in
            g.addTask { await done.value }
            g.addTask { try? await Task.sleep(nanoseconds: 3_000_000_000); return false }
            let r = await g.next() ?? false
            g.cancelAll()
            return r
        }
        #expect(finished)
    }

    @Test func registryExpiresEntries() async {
        let start = FixedClock()
        let registry = OwnWriteRegistry(clock: start, ttl: 5)
        await registry.register(path: "a.md", hash: "h")
        #expect(await registry.pendingCount == 1)
        let late = OwnWriteRegistry(clock: start.advanced(bySeconds: 10), ttl: 5)
        #expect(await late.consume(path: "a.md", hash: "h") == false)
        #expect(await registry.consume(path: "a.md", hash: "other") == false)
        #expect(await registry.consume(path: "a.md", hash: "h"))
        #expect(await registry.consume(path: "a.md", hash: "h") == false)
    }

    @Test func mergeRules() {
        var p: [String: FileChange.Kind] = [:]
        PollingFileWatcher.merge(&p, FileChange(path: "a", kind: .created))
        PollingFileWatcher.merge(&p, FileChange(path: "a", kind: .modified))
        #expect(p["a"] == .created)
        PollingFileWatcher.merge(&p, FileChange(path: "a", kind: .deleted))
        #expect(p["a"] == nil)
    }
}
