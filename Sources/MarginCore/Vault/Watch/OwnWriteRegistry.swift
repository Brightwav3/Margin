import Foundation

/// Remembers writes the app made itself so the watcher does not report them back as external
/// changes (no feedback loop). The store calls `register(path:hash:)` right before writing; the
/// watcher calls `consume(path:hash:)` when it sees the resulting content. Entries expire after
/// `ttl` seconds (measured with the injected `Clock`).
public actor OwnWriteRegistry {
    /// Hash (hex string) to register for a deletion the app performs itself.
    public static let deletedHash = "<deleted>"

    private struct Entry { let hash: String; let expires: Date }

    private let clock: any Clock
    private let ttl: TimeInterval
    private var entries: [String: [Entry]] = [:]

    public init(clock: any Clock = SystemClock(), ttl: TimeInterval = 5) {
        self.clock = clock
        self.ttl = ttl
    }

    /// Announces that `path` is about to be written with content whose hash is `hash`.
    public func register(path: String, hash: String) {
        prune()
        entries[path, default: []].append(Entry(hash: hash, expires: clock.now.addingTimeInterval(ttl)))
    }

    /// Typed variant of `register(path:hash:)` using the store's SHA-256 version.
    public func register(path: String, hash: ContentHash) {
        register(path: path, hash: hash.hex)
    }

    /// Typed variant of `consume(path:hash:)`.
    public func consume(path: String, hash: ContentHash) -> Bool {
        consume(path: path, hash: hash.hex)
    }

    /// `true` (and forgets the entry) when a live registration matches `path` and `hash`.
    public func consume(path: String, hash: String) -> Bool {
        prune()
        guard var list = entries[path], let i = list.firstIndex(where: { $0.hash == hash }) else { return false }
        list.remove(at: i)
        entries[path] = list.isEmpty ? nil : list
        return true
    }

    /// `true` when the observed hash matches the latest announced write for `path`. Event-driven
    /// watchers may coalesce several writes and only read the final bytes, so an older matching
    /// registration cannot prove that the final edit came from this process.
    func consumeLatest(path: String, hash: String) -> Bool {
        prune()
        guard let latest = entries[path]?.last, latest.hash == hash else { return false }
        entries[path] = nil
        return true
    }

    /// Withdraws a registration whose write never happened (e.g. it failed before the rename).
    public func forget(path: String, hash: String) {
        _ = consume(path: path, hash: hash)
    }

    /// Typed variant of `forget(path:hash:)`.
    public func forget(path: String, hash: ContentHash) {
        forget(path: path, hash: hash.hex)
    }

    /// Number of live registrations (for tests and diagnostics).
    public var pendingCount: Int {
        prune()
        return entries.values.reduce(0) { $0 + $1.count }
    }

    private func prune() {
        let now = clock.now
        for (path, list) in entries {
            let live = list.filter { $0.expires > now }
            entries[path] = live.isEmpty ? nil : live
        }
    }
}
