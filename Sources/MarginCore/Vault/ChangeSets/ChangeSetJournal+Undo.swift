import Foundation

extension RecordedOperation {
    /// The entry that describes reversing this operation.
    fileprivate func inverseEntry(noteID: NoteID?) -> ChangeSet.Entry {
        switch kind {
        case .write: .init(path: path, kind: .modified, noteID: noteID, beforeHash: afterHash, afterHash: beforeHash)
        case .create: .init(path: path, kind: .deleted, noteID: noteID, beforeHash: afterHash)
        case .move: .init(path: fromPath ?? path, kind: .moved, noteID: noteID, fromPath: path)
        case .trash: .init(path: path, kind: .created, noteID: noteID, afterHash: beforeHash)
        }
    }
}

extension ChangeSetJournal {
    /// What reversing one operation requires of the file system as it is now.
    private enum Verdict {
        /// The file is exactly as the change set left it: restore directly.
        case direct
        /// The file changed since; the undo was merged into the current text.
        case merged(current: Data, result: Data)
    }

    /// Reverses the committed change set `id` as one recorded transaction (so it can be undone
    /// again: redo), or, for `dryRun`, only checks that it can be reversed and reports what would
    /// change.
    ///
    /// - Throws: `.notFound` for an unknown, expired or incomplete record; `.conflict` when a file
    ///   changed since (see `UndoMode`), with nothing changed; `.invalid` when the record holds a
    ///   trashed folder (its content was never captured).
    func undo(id: String, actor: Actor, mode: UndoMode, dryRun: Bool) async throws -> Committed {
        let (original, ops) = try await operations(of: id)
        if ops.contains(where: { $0.kind == .trash && $0.restorable == false }) {
            throw MarginError.invalid("Change set \(id) trashed a folder, which undo cannot restore (it is in the trash)")
        }
        var noteIDs: [String: NoteID] = [:]
        for entry in original.entries {
            guard let note = entry.noteID else { continue }
            noteIDs[entry.path] = note
            if let from = entry.fromPath { noteIDs[from] = note }
        }
        let known = noteIDs

        // Fail fast, before anything is touched: check the last operation on every path.
        var seen = Set<String>()
        for op in ops.reversed() {
            let paths = [op.path] + (op.fromPath.map { [$0] } ?? [])
            if paths.contains(where: seen.contains) { continue }
            seen.formUnion(paths)
            _ = try await verdict(for: op, mode: mode)
        }

        let planned = ops.reversed().map { $0.inverseEntry(noteID: known[$0.path] ?? $0.fromPath.flatMap { known[$0] }) }
        if dryRun {
            let stamp = ContentHash(of: "dry|\(id)|\(actor.label)|\(clock.now.timeIntervalSince1970)").hex.prefix(16)
            let preview = ChangeSet(id: "dry-\(stamp)", actor: actor, timestamp: clock.now, entries: planned,
                                    isDryRun: true, revertsID: id)
            return Committed(changeSet: preview, operations: [])
        }

        let store = self.store
        let result = try await transaction(
            actor: actor, idempotencyKey: nil, revertsID: id,
            noteID: { known[$0] },
            body: {
                var entries = planned
                for op in ops.reversed() {
                    let verdict = try await ChangeSetJournal.verdict(for: op, mode: mode, store: store)
                    if case .merged(let current, let merged) = verdict {
                        let key = op.path
                        if let i = entries.firstIndex(where: { $0.path == key }) {
                            entries[i].beforeHash = ContentHash(of: current).hex
                            entries[i].afterHash = ContentHash(of: merged).hex
                            entries[i].merged = true
                        }
                    }
                    try await ChangeSetJournal.apply(op, verdict: verdict, store: store)
                }
                return entries
            })
        return result
    }

    // MARK: Checking

    private func verdict(for op: RecordedOperation, mode: UndoMode) async throws -> Verdict {
        try await Self.verdict(for: op, mode: mode, store: store)
    }

    private static func conflict(_ message: String, path: String, current: Data? = nil,
                                 merge: ThreeWayMerge.Result? = nil) -> MarginError {
        .conflict("Cannot undo: \(message)",
                  ConflictDetail(path: path, currentVersion: current.map { ContentHash(of: $0).hex },
                                 mergedText: merge?.text, conflictCount: merge?.conflictCount))
    }

    private static func bytes(_ path: VaultPath, in store: VaultStore) async -> Data? {
        try? await store.readData(path).data
    }

    private static func verdict(for op: RecordedOperation, mode: UndoMode, store: VaultStore) async throws -> Verdict {
        let path = try VaultPath(op.path)
        switch op.kind {
        case .write:
            guard let before = op.before, let after = op.after else { throw MarginError.notFound("Incomplete undo record for \(op.path)") }
            guard let current = await bytes(path, in: store) else {
                throw conflict("\(op.path) no longer exists", path: op.path)
            }
            if ContentHash(of: current).hex == op.afterHash { return .direct }
            guard mode == .merge else {
                throw conflict("\(op.path) changed after this change", path: op.path, current: current)
            }
            guard let base = String(validating: after, as: UTF8.self),
                  let ours = String(validating: before, as: UTF8.self),
                  let theirs = String(validating: current, as: UTF8.self) else {
                throw conflict("\(op.path) changed after this change and is not text that can be merged", path: op.path, current: current)
            }
            let merged = ThreeWayMerge.merge(base: base, ours: ours, theirs: theirs, oursLabel: "undone", theirsLabel: "current")
            guard !merged.hasConflicts else {
                throw conflict("\(op.path) was edited in the same place after this change", path: op.path, current: current, merge: merged)
            }
            return .merged(current: current, result: Data(merged.text.utf8))
        case .create:
            guard let current = await bytes(path, in: store), ContentHash(of: current).hex == op.afterHash else {
                throw conflict("\(op.path) changed or disappeared after it was created", path: op.path,
                               current: await bytes(path, in: store))
            }
            return .direct
        case .move:
            guard let from = op.fromPath.flatMap({ try? VaultPath($0) }) else {
                throw MarginError.notFound("Incomplete undo record for \(op.path)")
            }
            guard await store.exists(path) else { throw conflict("\(op.path) is not where the move left it", path: op.path) }
            guard !(await store.exists(from)) else { throw conflict("\(from) exists again, the file cannot be moved back", path: from.rawValue) }
            return .direct
        case .trash:
            guard op.before != nil else { throw MarginError.notFound("Incomplete undo record for \(op.path)") }
            guard !(await store.exists(path)) else {
                throw conflict("\(op.path) exists again, the deleted file cannot be restored over it", path: op.path,
                               current: await bytes(path, in: store))
            }
            return .direct
        }
    }

    // MARK: Applying

    private static func apply(_ op: RecordedOperation, verdict: Verdict, store: VaultStore) async throws {
        let path = try VaultPath(op.path)
        switch op.kind {
        case .write:
            guard let before = op.before, let afterHash = op.afterHash, let expected = ContentHash(hex: afterHash) else {
                throw MarginError.notFound("Incomplete undo record for \(op.path)")
            }
            switch verdict {
            case .direct: try await store.writeData(path, data: before, expectedVersion: expected)
            case .merged(let current, let merged):
                try await store.writeData(path, data: merged, expectedVersion: ContentHash(of: current))
            }
        case .create:
            try await store.trash(path)
        case .move:
            guard let from = op.fromPath.flatMap({ try? VaultPath($0) }) else {
                throw MarginError.notFound("Incomplete undo record for \(op.path)")
            }
            try await store.rename(path, to: from)
        case .trash:
            guard let before = op.before else { throw MarginError.notFound("Incomplete undo record for \(op.path)") }
            try await store.createData(path, data: before)
        }
    }
}
