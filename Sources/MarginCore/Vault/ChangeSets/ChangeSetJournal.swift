import Foundation

/// The write-ahead journal behind `ChangeSetStore` (spec 05 §12, `.margin/changesets/`).
///
/// A *transaction* groups every file operation the `VaultStore` performs for one logical write
/// (save, create, move with its link rewrites, delete, undo). Filesystems have no multi-file
/// atomic commit, so the group is made all-or-nothing like this:
///
/// 1. **Write-ahead.** Before each operation the store announces it (`WriteCapture`); the journal
///    writes `<seq>~<id>.op-NNNN.json` (atomically, fsynced) holding the bytes about to be
///    replaced or trashed. Only then does the operation run.
/// 2. **Apply.** The operations run one after another, each atomic on its own.
/// 3. **Commit.** `<seq>~<id>.meta.json` (the `ChangeSet`) is written atomically. Its existence is
///    the commit point.
///
/// If anything throws before the commit, the applied operations are reverted in reverse order and
/// the op files removed. If the process dies, the next `open` finds op files without a meta file
/// and does the same (rolls back), so a group is either fully there or fully absent. A file that
/// was changed by someone else meanwhile (neither the recorded before nor after state) is never
/// touched by a rollback; it is reported in `recovery.problems`.
///
/// Committed records double as the undo data. They expire by `ChangeSetRetention`; expiry removes
/// op files first and the meta file last, so a crash while expiring can never look like an
/// interrupted transaction.
///
/// One app instance per vault is assumed (the same assumption the store's temp-file cleanup makes).
actor ChangeSetJournal {
    /// A finished transaction.
    struct Committed: Sendable {
        var changeSet: ChangeSet
        /// The operations that were applied, in order.
        var operations: [RecordedOperation]
    }

    /// What `open` did about transactions a previous run left unfinished.
    struct RecoveryReport: Sendable, Equatable {
        /// Ids of interrupted transactions that were rolled back.
        var rolledBack: [String] = []
        /// Files a rollback left alone because they no longer matched (someone else changed them).
        var problems: [String] = []
        /// Record files that could not be decoded (left in place).
        var unreadable: [String] = []
    }

    private struct Slot {
        var seq: Int
        var changeSet: ChangeSet
        var operationCount: Int
    }

    static let format = 1

    let store: VaultStore
    let clock: any Clock
    let retention: ChangeSetRetention
    private(set) var recovery = RecoveryReport()

    private var slots: [Slot] = []          // committed, oldest first
    private var nextSeq = 1
    private var counter = 0
    private let nonce = UUID().uuidString
    private let gate = AsyncMutex()

    private init(store: VaultStore, clock: any Clock, retention: ChangeSetRetention) {
        self.store = store; self.clock = clock; self.retention = retention
    }

    /// Opens the journal of `store`: rolls back interrupted transactions, loads the committed
    /// records and applies retention.
    static func open(store: VaultStore, clock: any Clock, retention: ChangeSetRetention = .standard) async throws -> ChangeSetJournal {
        let journal = ChangeSetJournal(store: store, clock: clock, retention: retention)
        try await journal.load()
        return journal
    }

    // MARK: File names

    private static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    static func baseName(seq: Int, id: String) -> String { "\(pad(seq, 10))~\(id)" }
    static func opFileName(base: String, index: Int) -> String { "\(base).op-\(pad(index, 4)).json" }
    static func metaFileName(base: String) -> String { "\(base).meta.json" }

    static func path(_ name: String) -> VaultPath { VaultPath.internalChangeSets.appendingUnchecked(name) }

    /// `(seq, id, part)` of `0000000012~cs-abc.op-0001.json`; `nil` for foreign files.
    private static func parse(_ name: String) -> (seq: Int, id: String, part: String)? {
        guard let tilde = name.firstIndex(of: "~"), tilde != name.startIndex else { return nil }
        guard let seq = Int(name[..<tilde]) else { return nil }
        let rest = name[name.index(after: tilde)...]
        guard let dot = rest.firstIndex(of: ".") else { return nil }
        return (seq, String(rest[..<dot]), String(rest[rest.index(after: dot)...]))
    }

    // MARK: Loading and recovery

    private func load() async throws {
        let names = try await store.appDataFileNames(in: VaultPath.internalChangeSets)
        var groups: [String: (seq: Int, id: String, parts: [String])] = [:]
        for name in names {
            guard let p = Self.parse(name) else { continue }
            let base = Self.baseName(seq: p.seq, id: p.id)
            groups[base, default: (p.seq, p.id, [])].parts.append(p.part)
        }
        for (base, group) in groups.sorted(by: { $0.value.seq < $1.value.seq }) {
            nextSeq = max(nextSeq, group.seq + 1)
            if group.parts.contains("meta.json") {
                do {
                    let data = try await store.readData(Self.path(Self.metaFileName(base: base))).data
                    let record = try JSONDecoder().decode(CommittedRecord.self, from: data)
                    slots.append(Slot(seq: group.seq, changeSet: record.changeSet, operationCount: record.operationCount))
                } catch {
                    recovery.unreadable.append(base)
                }
            } else {
                // No commit point: an interrupted transaction. Roll it back.
                let problems = await rollback(base: base)
                recovery.rolledBack.append(group.id)
                recovery.problems += problems
            }
        }
        slots.sort { $0.seq < $1.seq }
        await applyRetention()
    }

    // MARK: Queries

    /// Committed change sets, newest first.
    func changes(limit: Int?) async -> [ChangeSet] {
        await applyRetention()
        let all = slots.reversed().map(\.changeSet)
        guard let limit else { return all }
        return Array(all.prefix(max(0, limit)))
    }

    func change(id: String) async throws -> ChangeSet {
        await applyRetention()
        guard let slot = slots.first(where: { $0.changeSet.id == id }) else {
            throw MarginError.notFound("No change set \(id) (unknown or expired)")
        }
        return slot.changeSet
    }

    /// The recorded operations of a committed change set.
    func operations(of id: String) async throws -> (changeSet: ChangeSet, operations: [RecordedOperation]) {
        await applyRetention()
        guard let slot = slots.first(where: { $0.changeSet.id == id }) else {
            throw MarginError.notFound("No change set \(id) (unknown or expired)")
        }
        let base = Self.baseName(seq: slot.seq, id: id)
        var ops: [RecordedOperation] = []
        for i in 1...max(slot.operationCount, 1) where slot.operationCount > 0 {
            do {
                let data = try await store.readData(Self.path(Self.opFileName(base: base, index: i))).data
                ops.append(try JSONDecoder().decode(RecordedOperation.self, from: data))
            } catch {
                throw MarginError.notFound("The undo data of change set \(id) is incomplete")
            }
        }
        return (slot.changeSet, ops)
    }

    // MARK: Transactions

    /// Runs `body` (which performs store operations) as one all-or-nothing, recorded group.
    ///
    /// - Parameters:
    ///   - body: performs the writes through the `VaultStore` and returns the `ChangeSet` entries it
    ///     can describe (with note ids); files it touched that it did not describe (for example
    ///     notes rewritten by a rename observer) are added automatically.
    ///   - noteID: resolves the note id of such an automatically added file.
    /// - Returns: the committed change set. When `body` performed no operation nothing is recorded
    ///   and the change set is not stored (`operations` is empty).
    func transaction(
        actor: Actor,
        idempotencyKey: String?,
        revertsID: String? = nil,
        noteID: @escaping @Sendable (String) async -> NoteID? = { _ in nil },
        body: @Sendable () async throws -> [ChangeSet.Entry]
    ) async throws -> Committed {
        await gate.lock()
        defer { gate.unlock() }

        let now = clock.now
        counter += 1
        let id = "cs-" + String(ContentHash(of: "\(nonce)|\(counter)|\(now.timeIntervalSince1970)|\(actor.label)").hex.prefix(16))
        let seq = nextSeq
        nextSeq += 1
        let base = Self.baseName(seq: seq, id: id)
        let capture = TransactionCapture(store: store, base: base)

        var entries: [ChangeSet.Entry]
        do {
            entries = try await WriteCaptureContext.$current.withValue(capture) { try await body() }
        } catch {
            _ = await rollback(base: base)
            throw error
        }
        let ops = capture.operations
        if ops.isEmpty {
            return Committed(changeSet: ChangeSet(id: id, actor: actor, timestamp: now, entries: entries,
                                                  idempotencyKey: idempotencyKey, revertsID: revertsID),
                             operations: [])
        }
        // Files touched but not described by the caller.
        var covered = Set(entries.flatMap { [$0.path] + ($0.fromPath.map { [$0] } ?? []) })
        for op in ops {
            let paths = [op.path] + (op.fromPath.map { [$0] } ?? [])
            if paths.contains(where: covered.contains) { continue }
            entries.append(op.derivedEntry(noteID: await noteID(op.path)))
            covered.formUnion(paths)
        }
        let changeSet = ChangeSet(id: id, actor: actor, timestamp: now, entries: entries,
                                  idempotencyKey: idempotencyKey, revertsID: revertsID)
        do {
            let record = CommittedRecord(format: Self.format, changeSet: changeSet, operationCount: ops.count)
            let data = try Self.encoder.encode(record)
            try await WriteCaptureContext.$current.withValue(nil) {
                try await store.writeData(Self.path(Self.metaFileName(base: base)), data: data)
            }
        } catch {
            // The commit point may still have been reached (for example only the folder sync
            // failed). If the record is on disk and valid, the group is committed.
            if !(await recordExists(base: base, id: id)) {
                _ = await rollback(base: base)
                throw error
            }
        }
        slots.append(Slot(seq: seq, changeSet: changeSet, operationCount: ops.count))
        await applyRetention()
        return Committed(changeSet: changeSet, operations: ops)
    }

    private func recordExists(base: String, id: String) async -> Bool {
        guard let data = try? await store.readData(Self.path(Self.metaFileName(base: base))).data,
              let record = try? JSONDecoder().decode(CommittedRecord.self, from: data) else { return false }
        return record.changeSet.id == id
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    // MARK: Retention

    private func applyRetention() async {
        let drop = retention.dropCount(timestamps: slots.map(\.changeSet.timestamp), now: clock.now)
        guard drop > 0 else { return }
        for slot in slots.prefix(drop) {
            let base = Self.baseName(seq: slot.seq, id: slot.changeSet.id)
            // Op files first, the meta file last: see the type comment.
            var failed = false
            if slot.operationCount > 0 {
                for i in 1...slot.operationCount {
                    do { try await store.removeJournalFile(Self.path(Self.opFileName(base: base, index: i))) } catch { failed = true }
                }
            }
            if !failed { try? await store.removeJournalFile(Self.path(Self.metaFileName(base: base))) }
        }
        slots.removeFirst(drop)
    }

    // MARK: Rollback

    /// Reverts the operations recorded for `base` (newest first) and removes their op files.
    /// Returns the problems found (files that could not be restored safely).
    private func rollback(base: String) async -> [String] {
        var problems: [String] = []
        let names = (try? await store.appDataFileNames(in: VaultPath.internalChangeSets)) ?? []
        let prefix = base + ".op-"
        let opNames = names.filter { $0.hasPrefix(prefix) }.sorted(by: >)
        for name in opNames {
            let path = Self.path(name)
            guard let data = try? await store.readData(path).data,
                  let op = try? JSONDecoder().decode(RecordedOperation.self, from: data) else {
                problems.append("\(name): unreadable, left in place")
                continue
            }
            let outcome = await WriteCaptureContext.$current.withValue(nil) { await revert(op) }
            switch outcome {
            case .done:
                try? await store.removeJournalFile(path)
            case .skipped(let why):
                // Someone else's change: never overwritten. Nothing more this record can do.
                problems.append("\(op.path): \(why)")
                try? await store.removeJournalFile(path)
            case .failed(let why):
                // Keep the op file: the next open retries.
                problems.append("\(op.path): \(why), will retry")
            }
        }
        return problems
    }

    private enum RevertOutcome { case done, skipped(String), failed(String) }

    private func currentBytes(_ path: String) async -> Data? {
        guard let vp = try? VaultPath(path) else { return nil }
        return try? await store.readData(vp).data
    }

    /// Undoes one operation if it was applied, leaves it if it was not, skips it if the file is in
    /// a third state.
    private func revert(_ op: RecordedOperation) async -> RevertOutcome {
        do {
            let path = try VaultPath(op.path)
            switch op.kind {
            case .write:
                guard let before = op.before, let afterHash = op.afterHash else { return .skipped("incomplete record") }
                guard let current = await currentBytes(op.path) else { return .skipped("file is missing") }
                let hash = ContentHash(of: current).hex
                if hash == afterHash, let expected = ContentHash(hex: afterHash) {
                    try await store.writeData(path, data: before, expectedVersion: expected)
                    return .done
                }
                return hash == op.beforeHash ? .done : .skipped("changed by someone else, not restored")
            case .create:
                guard let current = await currentBytes(op.path) else {
                    return await store.exists(path) ? .skipped("is not a file") : .done
                }
                if ContentHash(of: current).hex == op.afterHash {
                    try await store.trash(path)
                    return .done
                }
                return .skipped("changed by someone else, not removed")
            case .move:
                guard let from = op.fromPath.flatMap({ try? VaultPath($0) }) else { return .skipped("incomplete record") }
                let toExists = await store.exists(path), fromExists = await store.exists(from)
                if toExists && !fromExists { try await store.rename(path, to: from); return .done }
                if !toExists && fromExists { return .done }
                return .skipped("neither the old nor the new location is in the expected state")
            case .trash:
                guard op.restorable != false, let before = op.before else { return .skipped("a folder in the trash is not restored") }
                if await store.exists(path) {
                    if let current = await currentBytes(op.path), ContentHash(of: current).hex == op.beforeHash { return .done }
                    return .skipped("something else is at this path now; the original is in the trash")
                }
                try await store.createData(path, data: before)
                return .done
            }
        } catch {
            return .failed("\(error)")
        }
    }
}

/// Persists each announced operation (write-ahead) and remembers it for the transaction.
final class TransactionCapture: WriteCapture, @unchecked Sendable {
    private let store: VaultStore
    private let base: String
    private let lock = NSLock()
    private var recorded: [RecordedOperation] = []

    init(store: VaultStore, base: String) { self.store = store; self.base = base }

    var operations: [RecordedOperation] { lock.withLock { recorded } }

    func willApply(_ operation: CapturedOperation) async throws {
        let op = RecordedOperation(operation)
        let index = lock.withLock { recorded.count + 1 }
        let data = try ChangeSetJournal.encoder.encode(op)
        let path = VaultPath.internalChangeSets.appendingUnchecked(ChangeSetJournal.opFileName(base: base, index: index))
        // The record itself must not be captured.
        try await WriteCaptureContext.$current.withValue(nil) {
            try await store.writeData(path, data: data)
        }
        lock.withLock { recorded.append(op) }
    }
}

extension VaultPath {
    /// This path plus one component that is known to be valid (journal file names).
    func appendingUnchecked(_ component: String) -> VaultPath { VaultPath(unchecked: components + [component]) }
}
