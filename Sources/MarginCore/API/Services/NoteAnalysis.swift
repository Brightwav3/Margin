/// Facts derived from a note's text and from the links between notes (read only): the outline, the
/// backlinks with context, the outgoing links, the inspector numbers and the properties.
///
/// Implementations: `FixtureNoteAnalysis` and `VaultNoteAnalysis` (over the note index). Rules both
/// obey (checked by `Tests/Conformance/NoteAnalysisConformanceTests.swift`):
///
/// - **Lines** are 1-based within `Note.text` (the body without frontmatter), for every method.
/// - **Outline:** the ATX headings outside code, in text order.
/// - **Backlinks:** one entry per link that resolves to the note (an ambiguous link counts for every
///   candidate), sorted by source title (case-insensitive), then source id, then line. Links from the
///   note to itself and links from things that are not notes (`_course.md`, the inbox) do not count.
/// - **Outgoing:** every wikilink of the note in text order, including links to notes that do not
///   exist yet (`.notCreated`) and ambiguous ones.
/// - **Stats:** `stats(id:text:)` with `text == nil` describes the saved note. With editor text it
///   describes that text as the note's body, so the inspector follows typing; `backlinks` and
///   `properties` still come from the saved note. Implementations recompute only what an edit changed.
/// - **Properties:** the frontmatter keys in file order, with the registered type of the key, else
///   the type inferred from the value. Unknown keys are included.
/// - **Errors:** an unknown note id throws `MarginError.notFound`.
public protocol NoteAnalysis: Sendable {
    func outline(id: NoteID) async throws -> [OutlineItem]
    func backlinks(id: NoteID) async throws -> [NoteBacklink]
    func outgoing(id: NoteID) async throws -> [OutgoingLink]
    func stats(id: NoteID, text: String?) async throws -> NoteStats
    func properties(id: NoteID) async throws -> [NoteProperty]
}

extension NoteAnalysis {
    /// Stats of the saved note.
    public func stats(id: NoteID) async throws -> NoteStats { try await stats(id: id, text: nil) }
}
