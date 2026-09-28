import Foundation
import Testing
@testable import MarginCore

/// The store announces its writes to an `OwnWriteRegistry`; a `PollingFileWatcher` over the same
/// vault must stay silent for them and still report edits made by anyone else.
@Suite struct VaultStoreWatcherIntegrationTests {
    private func setUp() async throws -> (dir: TempDir, store: VaultStore, watcher: PollingFileWatcher, registry: OwnWriteRegistry) {
        let dir = TempDir()
        try dir.seed("Fall/a.md", Data("seed a".utf8))
        try dir.seed("Fall/sub/b.md", Data("seed b".utf8))
        try dir.seed("Fall/sub/_files/pic.png", Data([1, 2, 3]))
        // Generous TTL: on a loaded machine the poller can lag far behind the writes.
        let registry = OwnWriteRegistry(ttl: 120)
        let store = try await VaultStore.open(root: dir.url, ownWrites: registry)
        let watcher = PollingFileWatcher(root: store.root, interval: 0.1, ownWrites: registry)
        return (dir, store, watcher, registry)
    }

    @Test func ownWritesProduceNoEventsButExternalEditsDo() async throws {
        let (dir, store, watcher, _) = try await setUp()
        let c = Collector(watcher.changes())
        defer { c.stop() }

        let v1 = try await store.create(vp("Fall/new.md"), content: "hello")
        try await store.write(vp("Fall/a.md"), content: "own edit", expectedVersion: ContentHash(of: "seed a"))
        try await store.write(vp("Fall/new.md"), content: "hello again", expectedVersion: v1)
        try await store.rename(vp("Fall/a.md"), to: vp("Fall/renamed.md"))
        try await store.rename(vp("Fall/sub"), to: vp("Fall/moved"))
        try await store.trash(vp("Fall/new.md"))

        // An external edit made after the app's own writes is reported.
        try Data("external".utf8).write(to: dir.file("Fall/ext.md"))
        #expect(await c.wait { $0.contains(FileChange(path: "Fall/ext.md", kind: .created)) })
        await c.settle()
        #expect(c.all == [FileChange(path: "Fall/ext.md", kind: .created)], "got \(c.all)")
        // Registrations for intermediate states the poller never saw are not consumed; they
        // simply expire after the registry's TTL.
    }

    @Test func externalEditToAFileTheStoreJustWroteIsStillReported() async throws {
        let (dir, store, watcher, _) = try await setUp()
        let c = Collector(watcher.changes())
        defer { c.stop() }

        try await store.write(vp("Fall/a.md"), content: "own edit")
        await c.settle()
        #expect(c.all.isEmpty)
        try Data("someone else".utf8).write(to: dir.file("Fall/a.md"))
        #expect(await c.wait { $0.contains(FileChange(path: "Fall/a.md", kind: .modified)) })
    }

    @Test func noFeedbackLoopAfterManyOwnWrites() async throws {
        let (_, store, watcher, _) = try await setUp()
        let c = Collector(watcher.changes())
        defer { c.stop() }
        for i in 0..<20 { try await store.write(vp("Fall/loop.md"), content: "rev \(i)") }
        await c.settle()
        #expect(c.all.isEmpty)
    }

    @Test func failedWriteLeavesNoRegistration() async throws {
        let (_, store, _, registry) = try await setUp()
        await #expect(throws: MarginError.self) {
            try await store.write(vp("Fall/a.md"), content: "x", expectedVersion: ContentHash(of: "stale"))
        }
        await #expect(throws: MarginError.self) { try await store.rename(vp("Fall/a.md"), to: vp("Fall/sub/b.md")) }
        await #expect(throws: MarginError.self) { try await store.trash(vp("Fall/nope.md")) }
        #expect(await registry.pendingCount == 0)
    }
}
