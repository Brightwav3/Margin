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
func requireBaseVersion(_ base: String?, matches current: String, what: String) throws {
    if let base, base != current {
        throw MarginError.conflict("\(what) changed since version \(base.prefix(12)) (now \(current.prefix(12)))")
    }
}
