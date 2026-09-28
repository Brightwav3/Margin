/// The inbox: captures that have no course yet (`_inbox/`, spec 05 §6) and their triage (M8-08).
///
/// Implementations: `FixtureInboxService` and `VaultInboxService`. Rules both obey (checked by
/// `Tests/Conformance/InboxServiceConformanceTests.swift`):
///
/// - **items:** newest `captured` first, ties by id. An item's `id` names it in `triage` and
///   `delete` (vault: the file name without `.md`, fixture: the fixture id or, for a new capture,
///   the file name). A file in `_inbox/` without frontmatter is an item too (kind `note`, source
///   `share`, captured as its name says or now); an empty file is not.
/// - **triage as task** (`kind` is `task`, given or the item's own): appends
///   `- [ ] <text> @yyyy-MM-dd ^t-xxxx` to `<semester>/<course>/Tasks.md` (created when missing,
///   see `CaptureService`); a trailing `@date` of the item text becomes the due date, `when`
///   overrides it. The inbox file goes to the trash. `ChangeSet`: the Tasks note `.created` or
///   `.modified`, then the inbox file `.deleted`.
/// - **triage as note** (`note`, `link`, `image`): the inbox file becomes a note in the course
///   folder (frontmatter `id`, `date` = `when` or the day captured, `class`, `type: note`; title
///   from the first line) and the inbox file goes to the trash. `ChangeSet`: one `.moved` entry
///   (`path` new, `fromPath` the inbox file, `noteID` set).
/// - **delete:** moves the inbox file to the trash (`.deleted`); it is never destroyed.
/// - **Errors:** unknown item or course `.notFound`; stale `baseVersion` (hash of the inbox file
///   as written, the `afterHash` of the capture that created it) `.conflict`. Nothing changes.
/// - **Write context:** as in `NoteRepository`: `dryRun` changes nothing and returns the entries
///   it would make; a repeated `idempotencyKey` of the same actor returns the first `ChangeSet`.
public protocol InboxService: Sendable {
    /// All inbox items, newest first.
    func items() async throws -> [InboxItem]

    /// Moves an item out of the inbox into `course`, as a task or a note.
    func triage(item: String, course: CourseID, when: LocalDate?, kind: InboxKind?, actor: Actor,
                baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet

    /// Moves an item to the trash.
    func delete(item: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet
}
