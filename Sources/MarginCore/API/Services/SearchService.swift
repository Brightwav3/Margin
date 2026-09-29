/// Finding notes: the search field of the palette, the `[[` popup and the hover preview
/// (M10-01, M10-03, M10-05, M11-03).
///
/// Implementations: `FixtureSearchService` and `VaultSearchService`, both answering from the same
/// engine over the note index, so the two agree by construction; the conformance suite
/// `Tests/Conformance/SearchServiceConformanceTests.swift` checks the rules below on both.
///
/// **search**
/// - Words: the query is split into words (letters and digits); case and diacritics are ignored
///   (`mitoza` finds `Mitóza`). Every word must occur in the note (title, aliases, headings, tags
///   or text); the last word also matches as a prefix unless the query ends with a space.
/// - Ranking: BM25 with the title counting most, then headings, tags and text; best first, ties by
///   title (case-insensitive) then id.
/// - Filter: applied before ranking; see `SearchFilter`. An unknown course matches nothing.
/// - A query without words and a filter that restricts something lists the notes that pass the
///   filter, dated ones first (newest first), then undated, ties by title; `score` is `0`. A query
///   without words and no filter gives `[]`.
/// - Only live notes are searched: not `_course.md`, not the inbox, not archived semesters.
/// - Results follow saves and outside edits (the index is refreshed before answering).
/// - Errors: `filter.limit < 1` is `.invalid`.
///
/// **suggestLinks** (see `LinkSuggester` for the ranking rules): `prefix` is the text after `[[`;
/// `course` and `note` describe the note being edited (its course's notes come first; it is not
/// suggested to itself, and `#text` completes its headings).
///
/// **excerpt** (see `NoteExcerptProvider`): the first paragraph of a note or, with `heading`, of
/// that section. An unknown note is `.notFound`.
public protocol SearchService: Sendable {
    func search(query: String, filter: SearchFilter) async throws -> [SearchHit]

    func suggestLinks(prefix: String, course: CourseID?, note: NoteID?, limit: Int) async throws -> [LinkSuggestion]

    func excerpt(note: NoteID, heading: String?) async throws -> NoteExcerpt
}

extension SearchService {
    public func search(query: String) async throws -> [SearchHit] {
        try await search(query: query, filter: .none)
    }

    public func suggestLinks(prefix: String, course: CourseID? = nil, note: NoteID? = nil) async throws -> [LinkSuggestion] {
        try await suggestLinks(prefix: prefix, course: course, note: note, limit: 8)
    }

    public func excerpt(note: NoteID) async throws -> NoteExcerpt {
        try await excerpt(note: note, heading: nil)
    }
}
