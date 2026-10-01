import Foundation

/// Snapshot files in the fixture store's memory.
struct FixtureHistoryStorage: HistoryStorage {
    let owner: WeakOwner<FixtureStore>

    private func store() throws -> FixtureStore {
        guard let store = owner.value else { throw MarginError.invalid("The fixture store is gone") }
        return store
    }

    func names(note: NoteID) async throws -> [String] { try await store().historyNames(note: note) }
    func notes() async throws -> [NoteID] { try await store().historyNotes() }
    func read(note: NoteID, name: String) async throws -> Data { try await store().historyRead(note: note, name: name) }
    func write(note: NoteID, name: String, data: Data) async throws { try await store().historyWrite(note: note, name: name, data: data) }
    func remove(note: NoteID, name: String) async throws { try await store().historyRemove(note: note, name: name) }
}

struct FixtureHistoryHost: HistoryHost {
    let owner: WeakOwner<FixtureStore>

    private func store() throws -> FixtureStore {
        guard let store = owner.value else { throw MarginError.invalid("The fixture store is gone") }
        return store
    }

    func current(note: NoteID) async throws -> Note { try await store().open(id: note) }

    func save(note: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet {
        // `restore` records its own versions: the store's plain save takes no automatic snapshot.
        try await store().save(id: note, text: text, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                               idempotencyKey: idempotencyKey)
    }
}

extension FixtureStore {
    static func makeHistoryEngine(owner: WeakOwner<FixtureStore>, clock: any Clock) -> HistoryEngine {
        HistoryEngine(storage: FixtureHistoryStorage(owner: owner), host: FixtureHistoryHost(owner: owner), clock: clock)
    }

    /// The note save with the automatic `.save` snapshot of a real change (what `NoteRepository.save` does).
    func saveRecordingHistory(id: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                              idempotencyKey: String?) async throws -> ChangeSet {
        let changes = try save(id: id, text: text, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                               idempotencyKey: idempotencyKey)
        if !dryRun, !changes.entries.isEmpty, let note = try? open(id: id) {
            await history.autoSnapshot(note: id, text: note.text)
        }
        return changes
    }

    func historyNames(note: NoteID) -> [String] { (historyFiles[note] ?? [:]).keys.sorted() }

    func historyNotes() -> [NoteID] { historyFiles.filter { !$0.value.isEmpty }.keys.sorted() }

    /// What `VaultStore.usage` reports for a vault: note texts as UTF-8, snapshot files.
    func usage() -> VaultStats {
        VaultStats(noteCount: notes.count, noteBytes: notes.values.reduce(0) { $0 + Int64($1.content.utf8.count) },
                   attachmentCount: 0, attachmentBytes: 0,
                   historyBytes: historyFiles.values.flatMap(\.values).reduce(0) { $0 + Int64($1.count) })
    }

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
        engine = store.history
    }

    public func versions(note: NoteID) async throws -> [NoteVersion] { try await engine.versions(note: note) }
    public func recentVersions(limit: Int) async throws -> [NoteVersion] { try await engine.recentVersions(limit: limit) }
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
