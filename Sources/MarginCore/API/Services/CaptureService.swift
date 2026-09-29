/// Quick capture: turning a line of text into a `CaptureDraft` and saving it (M8-06).
///
/// Implementations: `FixtureCaptureService` and `VaultCaptureService`. Rules both obey (checked by
/// `Tests/Conformance/CaptureServiceConformanceTests.swift`; the file format is
/// `05-vault-spec.md` §6 and §3):
///
/// - **parse:** never throws for odd text; it recognises courses, `@`/natural dates, `#tags` and
///   a `note:`/`task:`/`link:` prefix (`QuickCaptureParser`). An empty line gives a draft with
///   empty `text`, which `commit` refuses.
/// - **commit without course:** creates `_inbox/<yyyy-MM-dd> <HHmm> <text>.md` (captured now, from
///   the `Clock`; `source: quick-capture`; `kind` of the draft). A due date and tags of a task
///   draft are written into the text as `@yyyy-MM-dd` and `#tag`. The `ChangeSet` has one `.created`
///   entry.
/// - **commit with course, kind `task`:** appends `- [ ] <text> #tag @yyyy-MM-dd ^t-xxxx` to the
///   course's task note `<semester>/<course>/Tasks.md`, which is created when missing. One
///   `.created` or `.modified` entry (with `noteID`).
/// - **commit with course, other kinds:** creates a note titled after the first line of the text
///   in the course (`type: note`, `date:` today, `tags:`); title taken: ` 2`, ` 3`, …
/// - **`attachTo`:** takes precedence over `course`: a task draft appends a task line to that
///   note, other drafts append the text as a paragraph. One `.modified` entry.
/// - **Errors:** empty text `.invalid`; unknown course or note `.notFound`. Nothing is written.
/// - **Write context:** `dryRun` returns the entries the write would make and changes nothing
///   (hashes of a task line differ from the real write, its `^id` is drawn at random);
///   `idempotencyKey` makes a repeated call return the first `ChangeSet`.
public protocol CaptureService: Sendable {
    /// Parses one line of quick-capture input against the courses and notes of the vault.
    func parse(_ input: String) async throws -> CaptureDraft

    /// Saves a draft as described above.
    func commit(_ draft: CaptureDraft, actor: Actor, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet
}
