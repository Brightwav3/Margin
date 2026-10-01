import Foundation

/// Snapshot files below `.margin/history/<note>/`, written atomically through `VaultStore`.
struct VaultHistoryStorage: HistoryStorage {
    let store: VaultStore

    /// The folder name of a note: the id itself when it is made of `A-Za-z0-9._-` (not starting with
    /// a dot), otherwise every other byte as `%XX`. Different ids never share a folder.
    static func folderName(for note: NoteID) -> String {
        let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-".utf8)
        var out = ""
        for (i, byte) in note.utf8.enumerated() {
            if safe.contains(byte), !(i == 0 && byte == UInt8(ascii: ".")) { out.unicodeScalars.append(Unicode.Scalar(byte)) }
            else { out += String(format: "%%%02X", byte) }
        }
        return out.isEmpty ? "%" : out
    }

    private func folder(_ note: NoteID) throws -> VaultPath {
        try VaultPath(components: [VaultPath.internalFolderName, "history", Self.folderName(for: note)])
    }

    /// Notes with a history folder; folder names decode back to note ids (`%XX` bytes).
    func notes() async throws -> [NoteID] {
        let root = try VaultPath(components: [VaultPath.internalFolderName, "history"])
        return try await store.listInternalFolders(in: root).compactMap(Self.noteID(fromFolder:))
    }

    static func noteID(fromFolder name: String) -> NoteID? {
        var bytes: [UInt8] = []
        let utf8 = Array(name.utf8)
        var k = 0
        while k < utf8.count {
            if utf8[k] == UInt8(ascii: "%") {
                guard k + 2 < utf8.count, let b = UInt8(String(decoding: utf8[(k + 1)...(k + 2)], as: UTF8.self), radix: 16) else { return nil }
                bytes.append(b); k += 3
            } else { bytes.append(utf8[k]); k += 1 }
        }
        let id = String(decoding: bytes, as: UTF8.self)
        return id.isEmpty ? nil : id
    }

    func names(note: NoteID) async throws -> [String] {
        try await store.listInternalFiles(in: try folder(note)).filter { $0.hasSuffix(HistoryEngine.fileExtension) }
    }

    func read(note: NoteID, name: String) async throws -> Data {
        try await store.readData(try folder(note).appending(name)).data
    }

    func write(note: NoteID, name: String, data: Data) async throws {
        try await store.writeData(try folder(note).appending(name), data: data)
    }

    func remove(note: NoteID, name: String) async throws {
        try await store.removeInternalFile(try folder(note).appending(name))
    }
}

struct VaultHistoryHost: HistoryHost {
    let owner: WeakOwner<VaultBackend>

    private func backend() throws -> VaultBackend {
        guard let backend = owner.value else { throw MarginError.invalid("The vault is closed") }
        return backend
    }

    func current(note: NoteID) async throws -> Note { try await backend().open(id: note) }

    func save(note: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet {
        // `restore` records its own versions: no automatic snapshot on top.
        try await backend().save(id: note, text: text, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                 idempotencyKey: idempotencyKey, autoSnapshot: false)
    }
}

/// `HistoryService` over a vault: snapshots in `.margin/history/` (spec 05 §9).
public struct VaultHistoryService: HistoryService {
    private let engine: HistoryEngine

    init(backend: VaultBackend) { engine = backend.history }

    /// The engine a vault backend owns: shared with the automatic snapshots of its save path.
    static func makeEngine(store: VaultStore, clock: any Clock, owner: WeakOwner<VaultBackend>) -> HistoryEngine {
        HistoryEngine(storage: VaultHistoryStorage(store: store), host: VaultHistoryHost(owner: owner), clock: clock)
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
