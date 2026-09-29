import Foundation

/// Remembers the result of writes by `(actor, idempotencyKey)` so a repeated call returns the first
/// result instead of writing again (contract rule 0). Bounded: the oldest keys are forgotten first.
struct IdempotencyCache: Sendable {
    private var results: [String: ChangeSet] = [:]
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int = 500) { self.capacity = capacity }

    private static func key(_ actor: Actor, _ key: String) -> String { "\(actor.label)|\(key)" }

    func lookup(actor: Actor, key: String?) -> ChangeSet? {
        key.flatMap { results[Self.key(actor, $0)] }
    }

    mutating func remember(_ changeSet: ChangeSet, actor: Actor) {
        guard let k = changeSet.idempotencyKey, !changeSet.isDryRun else { return }
        let full = Self.key(actor, k)
        if results[full] == nil { order.append(full) }
        results[full] = changeSet
        while order.count > capacity { results[order.removeFirst()] = nil }
    }
}

/// Builds `ChangeSet`s with ids that are unique per service instance and stable for equal input.
struct ChangeSetFactory: Sendable {
    private var counter = 0
    let clock: any Clock

    init(clock: any Clock) { self.clock = clock }

    mutating func make(actor: Actor, entries: [ChangeSet.Entry], isDryRun: Bool, idempotencyKey: String?) -> ChangeSet {
        counter += 1
        let stamp = clock.now
        let seed = "\(counter)|\(actor.label)|\(stamp.timeIntervalSince1970)|"
            + entries.map { "\($0.kind.rawValue):\($0.path):\($0.afterHash ?? "-")" }.joined(separator: ",")
        return ChangeSet(id: "cs-" + String(ContentHash(of: seed).hex.prefix(16)), actor: actor, timestamp: stamp,
                         entries: entries, isDryRun: isDryRun, idempotencyKey: idempotencyKey)
    }
}

/// Checks a caller's `baseVersion` against the stored version (contract rule 5).
func requireBaseVersion(_ base: String?, matches current: String, what: String, path: String? = nil) throws {
    if let base, base != current {
        throw MarginError.conflict("\(what) changed since version \(base.prefix(12)) (now \(current.prefix(12)))",
                                   ConflictDetail(path: path, currentVersion: current))
    }
}

/// Byte-exact text equality. Swift's `==` on `String` treats canonically equivalent texts (an `é`
/// as one scalar or as `e` plus an accent) as equal; a write that changes only such bytes must
/// still count as a change.
func sameBytes(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }

/// Remembers the text behind recent versions so a stale `baseVersion` can be turned into a
/// three-way merge base. Bounded by entry count and total size (oldest forgotten first); a
/// version it no longer knows simply cannot be merged.
struct TextVersionCache: Sendable {
    private var texts: [String: String] = [:]
    private var order: [String] = []
    private var bytes = 0
    private let capacity: Int
    private let maxBytes: Int

    init(capacity: Int = 256, maxBytes: Int = 32 * 1024 * 1024) {
        self.capacity = capacity; self.maxBytes = maxBytes
    }

    mutating func remember(_ text: String, version: String) {
        guard texts[version] == nil else { return }
        let size = text.utf8.count
        guard size <= maxBytes else { return }
        texts[version] = text
        order.append(version)
        bytes += size
        while order.count > capacity || bytes > maxBytes, let oldest = order.first {
            order.removeFirst()
            if let dropped = texts.removeValue(forKey: oldest) { bytes -= dropped.utf8.count }
        }
    }

    func lookup(_ version: String) -> String? { texts[version] }
}

/// How long and how many change sets are kept (spec 05 §12): at most `maxCount`, none older than
/// `maxAge`. Time comes from the `Clock`, so tests can move it.
public struct ChangeSetRetention: Sendable, Hashable {
    public var maxAge: TimeInterval
    public var maxCount: Int

    public init(maxAge: TimeInterval, maxCount: Int) { self.maxAge = maxAge; self.maxCount = maxCount }

    /// 30 days or 500 change sets.
    public static let standard = ChangeSetRetention(maxAge: 30 * 24 * 60 * 60, maxCount: 500)

    /// How many of the oldest entries to drop. `timestamps` are ordered oldest first.
    func dropCount(timestamps: [Date], now: Date) -> Int {
        var drop = max(0, timestamps.count - maxCount)
        while drop < timestamps.count, now.timeIntervalSince(timestamps[drop]) > maxAge { drop += 1 }
        return drop
    }
}
