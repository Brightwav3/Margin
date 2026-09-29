/// How `ChangeSetStore.undo` treats files that changed after the change set was made.
public enum UndoMode: String, Codable, Sendable, Hashable {
    /// Refuse (`.conflict`) when any file no longer has the version the change set left behind.
    /// Nothing is changed.
    case strict
    /// Merge instead: for note text the undo is applied as a three-way merge (base: what the
    /// change set wrote, ours: what it replaced, theirs: what is stored now), so later edits in
    /// other places are kept. Overlapping edits, and changes that are not about text (a created
    /// note edited since, a moved note, a deleted note recreated), still refuse with `.conflict`;
    /// for text the conflict's `ConflictDetail.mergedText` holds the merge with markers.
    case merge
}

/// Recorded groups of writes and their undo (contract rule 0, `10-agent-native.md` §1.4, §6).
///
/// Every write that returns a `ChangeSet` (not a dry run, not a failed write) is recorded here
/// with what is needed to reverse it. Implementations: `FixtureChangeSetStore` and
/// `VaultChangeSetStore`. Rules both obey (checked by
/// `Tests/Conformance/ChangeSetStoreConformanceTests.swift`):
///
/// - **Listing:** `changes` returns recorded change sets newest first, undo change sets included
///   (`ChangeSet.revertsID` says which one they reverted). Dry runs, empty change sets and failed
///   writes are not recorded.
/// - **Undo is a write:** it takes an `Actor`, records its own `ChangeSet` and can be undone
///   again (that is redo). `dryRun` reports what would change and records nothing.
/// - **Exact:** undoing a save restores the previous text and version, undoing a create removes
///   the note (to the trash), undoing a move moves the note back (with the links that were
///   rewritten), undoing a delete restores the note with its previous content.
/// - **Safe:** an undo is all-or-nothing. It never overwrites a change made since (strict mode
///   throws `.conflict` and changes nothing; see `UndoMode`).
/// - **Retention:** a change set is kept for 30 days, and at most the newest 500 are kept
///   (time from the `Clock`). An expired id is `.notFound`.
/// - **Errors:** unknown or expired id `.notFound`; changed since `.conflict`.
public protocol ChangeSetStore: Sendable {
    /// Recorded change sets, newest first; `limit` caps how many are returned.
    func changes(limit: Int?) async throws -> [ChangeSet]

    /// One recorded change set. Unknown or expired id: `.notFound`.
    func change(id: String) async throws -> ChangeSet

    /// Reverses the change set `id`; returns the `ChangeSet` of the undo itself (`revertsID == id`).
    func undo(id: String, actor: Actor, mode: UndoMode, dryRun: Bool) async throws -> ChangeSet
}

extension ChangeSetStore {
    /// All recorded change sets.
    public func changes() async throws -> [ChangeSet] { try await changes(limit: nil) }

    /// A strict, real undo.
    public func undo(id: String, actor: Actor) async throws -> ChangeSet {
        try await undo(id: id, actor: actor, mode: .strict, dryRun: false)
    }
}
