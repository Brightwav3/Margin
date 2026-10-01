/// Version history of notes (M11-08, spec 05 §9). Snapshots live in `.margin/history/<noteID>/`
/// (fixture: memory); the note files themselves are never touched except by `restore`.
///
/// Rules both implementations obey, checked by `Tests/Conformance/HistoryServiceConformanceTests.swift`:
///
/// - **Taking snapshots:** the caller (the editor session) calls `snapshot(note:reason:)` after every
///   save (`.save`) and when the note closes (`.close`). `.save` is taken at most once per 5 minutes
///   (`Clock`, measured from the newest version); `.close` is taken whenever the text differs from the
///   newest version. Saving identical text never makes a version. The result is the new version, or
///   `nil` when none was taken. An unknown note is `.notFound`.
/// - **Versions:** `versions(note:)` lists newest first; a note without history has none (unknown
///   notes too: history outlives a deleted note).
/// - **Retention:** the newest 50 versions and everything from the last 30 days are kept, whichever is
///   more; older versions beyond the 50 newest are dropped when a new one is taken.
/// - **Restore:** writes the old text as a new save (a `ChangeSet` like `NoteRepository.save`, with
///   `baseVersion` = `Note.version`, `dryRun`, idempotency) and nothing is deleted: the current text is
///   snapshotted first (when it differs from the newest version) and the restored text becomes the
///   newest version. Restoring the text that is current changes nothing.
/// - **Recent:** `recentVersions(limit:)` lists the newest versions of all notes together (File recovery),
///   newest first, at most `limit`; notes that were deleted still show their history.
/// - **Diff:** `diff(a, b)` goes from `a` to `b` (both of the same note); `diffWithCurrent` from a
///   version to the note as it is now.
public protocol HistoryService: Sendable {
    /// The versions of a note, newest first.
    func versions(note: NoteID) async throws -> [NoteVersion]

    /// The newest versions across all notes, newest first, at most `limit`.
    func recentVersions(limit: Int) async throws -> [NoteVersion]
    /// The note text of a version. `.notFound` when it was dropped or never existed.
    func text(of version: NoteVersion) async throws -> String

    /// Takes a snapshot of the note as it is now, unless the rules above say otherwise.
    func snapshot(note: NoteID, reason: SnapshotReason) async throws -> NoteVersion?

    /// Line diff from `a` to `b`. `.invalid` when they belong to different notes.
    func diff(_ a: NoteVersion, _ b: NoteVersion) async throws -> NoteDiff

    /// Line diff from `version` to the current text of its note.
    func diffWithCurrent(_ version: NoteVersion) async throws -> NoteDiff

    /// Writes the text of `version` as the note's new text.
    func restore(_ version: NoteVersion, actor: Actor, baseVersion: String?, dryRun: Bool,
                 idempotencyKey: String?) async throws -> ChangeSet
}
