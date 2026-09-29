import Foundation

/// Snapshot files in the fixture store's memory.
struct FixtureHistoryStorage: HistoryStorage {
    let store: FixtureStore

    func names(note: NoteID) async throws -> [String] { await store.historyNames(note: note) }
    func read(note: NoteID, name: String) async throws -> Data { try await store.historyRead(note: note, name: name) }
    func write(note: NoteID, name: String, data: Data) async throws { await store.historyWrite(note: note, name: name, data: data) }
    func remove(note: NoteID, name: String) async throws { await store.historyRemove(note: note, name: name) }
}

struct FixtureHistoryHost: HistoryHost {
    let store: FixtureStore

    func current(note: NoteID) async throws -> Note { try await store.open(id: note) }

    func save(note: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet {
        try await store.save(id: note, text: text, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                             idempotencyKey: idempotencyKey)
    }
}

extension FixtureStore {
    func historyNames(note: NoteID) -> [String] { (historyFiles[note] ?? [:]).keys.sorted() }

    func historyRead(note: NoteID, name: String) throws -> Data {
        guard let data = historyFiles[note]?[name] else { throw MarginError.notFound("No snapshot \(name)") }
        return data
    }

    func historyWrite(note: NoteID, name: String, data: Data) { historyFiles[note, default: [:]][name] = data }

    func historyRemove(note: NoteID, name: String) { historyFiles[note]?[name] = nil }
}

/// `HistoryService` over `Fixtures.week5`, in memory. Same engine as the vault implementation.
public struct FixtureHistoryService: HistoryService {
    private let engine: HistoryEngine

    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.init(store: FixtureStore(world: world, clock: clock), clock: clock)
    }

    init(store: FixtureStore, clock: any Clock) {
        engine = HistoryEngine(storage: FixtureHistoryStorage(store: store), host: FixtureHistoryHost(store: store), clock: clock)
    }

    public func versions(note: NoteID) async throws -> [NoteVersion] { try await engine.versions(note: note) }
    public func text(of version: NoteVersion) async throws -> String { try await engine.text(of: version) }
    public func snapshot(note: NoteID, reason: SnapshotReason) async throws -> NoteVersion? {
        try await engine.snapshot(note: note, reason: reason)
    }
    public func diff(_ a: NoteVersion, _ b: NoteVersion) async throws -> NoteDiff { try await engine.diff(a, b) }
    public func diffWithCurrent(_ version: NoteVersion) async throws -> NoteDiff { try await engine.diffWithCurrent(version) }
    public func restore(_ version: NoteVersion, actor: Actor, baseVersion: String?, dryRun: Bool,
                        idempotencyKey: String?) async throws -> ChangeSet {
        try await engine.restore(version, actor: actor, baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }
}
