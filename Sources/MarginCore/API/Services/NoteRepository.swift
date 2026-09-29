/// A change to a note made outside this service (another app, sync, an agent through the file
/// system), delivered by `NoteRepository.externalChanges`.
public struct NoteChange: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case created, modified, deleted
    }

    public var noteID: NoteID
    public var kind: Kind

    public init(noteID: NoteID, kind: Kind) {
        self.noteID = noteID; self.kind = kind
    }
}

/// Reading and writing notes.
///
/// Every write takes the write context of contract rule 0 and returns the `ChangeSet` it made:
///
/// - `actor`: who writes.
/// - `baseVersion`: the `Note.version` the caller worked from. When it no longer matches the stored
///   version the call throws `MarginError.conflict` and changes nothing. `nil` skips the check
///   (the last writer wins); agents must always send it.
/// - `dryRun`: compute and return the `ChangeSet`, change nothing.
/// - `idempotencyKey`: a repeated call with the same actor and key returns the first call's
///   `ChangeSet` and does not write again.
///
/// Implementations: `FixtureNoteRepository` and `VaultNoteRepository`. Rules both obey (checked by
/// `Tests/Conformance/NoteRepositoryConformanceTests.swift`):
///
/// - **Ordering:** `notes(course:)` lists dated notes first, newest date first, then undated notes;
///   ties by title (case-insensitive), then id.
/// - **What is a note:** files whose name starts with `_` (`_course.md`, `_grades.md`) and the
///   inbox are not notes; `notes(course: nil)` returns the notes of all courses.
/// - **Text:** `Note.text` is the body without frontmatter; `save` replaces the body and keeps
///   the frontmatter. `Note.version` is opaque and changes with every change of the note.
/// - **Errors:** unknown note or course `.notFound`; stale `baseVersion` `.conflict`; creating a
///   note whose title is taken in the course `.conflict`; an empty title `.invalid`.
/// - **Delete** moves the note to the trash, it is never destroyed.
public protocol NoteRepository: Sendable {
    /// Notes of a course, or of all courses when `course` is `nil`. Unknown course: `.notFound`.
    func notes(course: CourseID?) async throws -> [NoteSummary]

    /// The full note. Throws `.notFound` for an unknown id.
    func open(id: NoteID) async throws -> Note

    /// Replaces the body of a note. Saving identical text returns an empty `ChangeSet`.
    func save(id: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet

    /// Creates a note in a course. Its id is `<course>/<slug of title>`; the created id is in the
    /// returned entry's `noteID`. `baseVersion` has no meaning for a new note and is ignored.
    func create(course: CourseID, title: String, kind: NoteKind, text: String, actor: Actor,
                baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet

    /// Moves a note to another course. The id stays; links to the note are rewritten.
    /// Moving to the note's own course returns an empty `ChangeSet`.
    func move(id: NoteID, toCourse: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet

    /// Moves a note to the trash.
    func delete(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet

    /// A new stream on every access: changes made outside this service, in batches. The
    /// service's own writes are not reported.
    var externalChanges: AsyncStream<[NoteChange]> { get }
}
