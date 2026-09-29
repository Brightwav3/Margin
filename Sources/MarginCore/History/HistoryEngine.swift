import Foundation

/// Where snapshot files live: `.margin/history/<note>/<millis>.snap` in a vault, memory in the
/// fixture. `note` is the note id; names are opaque here.
protocol HistoryStorage: Sendable {
    func names(note: NoteID) async throws -> [String]
    func read(note: NoteID, name: String) async throws -> Data
    func write(note: NoteID, name: String, data: Data) async throws
    func remove(note: NoteID, name: String) async throws
}

/// The note side of history: the current text, and the ordinary save used by `restore`.
protocol HistoryHost: Sendable {
    func current(note: NoteID) async throws -> Note
    func save(note: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet
}

/// The behaviour of `HistoryService`, shared by the fixture and the vault implementation so the two
/// cannot drift. Stateless apart from serialising calls: what it knows lives in the storage.
actor HistoryEngine {
    private nonisolated let dedicatedExecutor = DedicatedExecutor(label: "margin.history-engine")
    nonisolated var unownedExecutor: UnownedSerialExecutor { dedicatedExecutor.asUnownedSerialExecutor() }
    static let throttle: TimeInterval = 5 * 60
    static let keepCount = 50
    static let keepDays = 30
    static let fileExtension = ".snap"

    private let storage: any HistoryStorage
    private let host: any HistoryHost
    private let clock: any Clock
    private let codec: any SnapshotCodec

    init(storage: any HistoryStorage, host: any HistoryHost, clock: any Clock,
         codec: any SnapshotCodec = SnapshotFormat.preferredCodec) {
        self.storage = storage; self.host = host; self.clock = clock; self.codec = codec
    }

    // MARK: Names

    static func millis(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1000).rounded()) }

    /// 13 digits, so names sort like the times they stand for.
    static func stem(_ millis: Int) -> String {
        let digits = String(max(millis, 0))
        return String(repeating: "0", count: max(0, 13 - digits.count)) + digits
    }

    private static func name(millis: Int) -> String { Self.stem(millis) + fileExtension }

    private static func millis(fromName name: String) -> Int? {
        guard name.hasSuffix(fileExtension) else { return nil }
        let stem = name.dropLast(fileExtension.count)
        return stem.count == 13 ? Int(stem) : nil
    }

    private static func id(_ note: NoteID, _ millis: Int) -> String { "\(note)@" + Self.stem(millis) }

    // MARK: Reading

    func versions(note: NoteID) async throws -> [NoteVersion] {
        var result: [NoteVersion] = []
        for name in try await storage.names(note: note) {
            guard let ms = Self.millis(fromName: name), let data = try? await storage.read(note: note, name: name),
                  let size = SnapshotFormat.size(of: data) else { continue }   // a damaged file is not a version
            result.append(NoteVersion(id: Self.id(note, ms), noteID: note, timestamp: Date(timeIntervalSince1970: Double(ms) / 1000), byteCount: size))
        }
        return result.sorted { $0.timestamp > $1.timestamp }
    }

    func text(of version: NoteVersion) async throws -> String {
        let name = Self.name(millis: Self.millis(version.timestamp))
        guard Self.id(version.noteID, Self.millis(version.timestamp)) == version.id else {
            throw MarginError.notFound("No version \(version.id)")
        }
        let data: Data
        do { data = try await storage.read(note: version.noteID, name: name) } catch MarginError.notFound {
            throw MarginError.notFound("Version \(version.id) no longer exists")
        }
        return try SnapshotFormat.decode(data)
    }

    // MARK: Snapshots

    /// The automatic `.save` snapshot after a note was written (spec 05 §9): the 5 minute rule applies
    /// and a failure is swallowed, because losing a version must never fail the save that caused it.
    func autoSnapshot(note id: NoteID, text: String) async {
        _ = try? await record(note: id, text: text, reason: .save)
    }

    func snapshot(note id: NoteID, reason: SnapshotReason) async throws -> NoteVersion? {
        let text = try await host.current(note: id).text
        return try await record(note: id, text: text, reason: reason)
    }

    /// Stores `text` as the newest version unless the rules say no; `force` skips the 5 minute limit.
    private func record(note id: NoteID, text: String, reason: SnapshotReason, force: Bool = false) async throws -> NoteVersion? {
        let existing = try await versions(note: id)
        let now = clock.now
        if let latest = existing.first {
            if reason == .save, !force, abs(now.timeIntervalSince(latest.timestamp)) < Self.throttle { return nil }
            if latest.byteCount == text.utf8.count, (try? await self.text(of: latest)) == text { return nil }
        }
        // Strictly newer than the newest version, even when the clock was set back or stopped.
        let ms = max(Self.millis(now), (existing.first.map { Self.millis($0.timestamp) } ?? Int.min) + 1)
        let data = SnapshotFormat.encode(text, codec: codec)
        try await storage.write(note: id, name: Self.name(millis: ms), data: data)
        let version = NoteVersion(id: Self.id(id, ms), noteID: id, timestamp: Date(timeIntervalSince1970: Double(ms) / 1000),
                                  byteCount: text.utf8.count)
        try await prune(note: id, versions: [version] + existing)
        return version
    }

    /// Keeps the newest `keepCount` versions and everything from the last `keepDays` days.
    private func prune(note id: NoteID, versions: [NoteVersion]) async throws {
        let cutoff = clock.now.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        for (i, v) in versions.enumerated() where i >= Self.keepCount && v.timestamp < cutoff {
            try await storage.remove(note: id, name: Self.name(millis: Self.millis(v.timestamp)))
        }
    }

    // MARK: Diff

    func diff(_ a: NoteVersion, _ b: NoteVersion) async throws -> NoteDiff {
        guard a.noteID == b.noteID else { throw MarginError.invalid("Versions of two different notes cannot be compared") }
        return LineDiff.diff(old: try await text(of: a), new: try await text(of: b))
    }

    func diffWithCurrent(_ version: NoteVersion) async throws -> NoteDiff {
        let now = try await host.current(note: version.noteID).text
        return LineDiff.diff(old: try await text(of: version), new: now)
    }

    // MARK: Restore

    func restore(_ version: NoteVersion, actor: Actor, baseVersion: String?, dryRun: Bool,
                 idempotencyKey: String?) async throws -> ChangeSet {
        let old = try await text(of: version)
        let current = try await host.current(note: version.noteID)
        if !dryRun {
            // Nothing is lost: what is there now becomes a version before it is replaced.
            _ = try await record(note: version.noteID, text: current.text, reason: .close)
        }
        let changes = try await host.save(note: version.noteID, text: old, actor: actor, baseVersion: baseVersion,
                                          dryRun: dryRun, idempotencyKey: idempotencyKey)
        if !dryRun { _ = try await record(note: version.noteID, text: old, reason: .close) }
        return changes
    }
}

/// A weak reference the history host uses to reach the backend that owns the engine, without a
/// retain cycle. Set once, right after the owner is initialised.
final class WeakOwner<T: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private weak var stored: T?
    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
