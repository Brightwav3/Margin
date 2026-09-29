/// `SearchService` over a vault: answers from the note index through the shared `SearchEngine`.
public struct VaultSearchService: SearchService {
    private let engine: SearchEngine

    init(backend: VaultBackend) {
        engine = SearchEngine(provider: { await backend.searchSources() })
    }

    public func search(query: String, filter: SearchFilter) async throws -> [SearchHit] {
        try await engine.search(query: query, filter: filter)
    }

    public func suggestLinks(prefix: String, course: CourseID?, note: NoteID?, limit: Int) async throws -> [LinkSuggestion] {
        try await engine.suggestLinks(prefix: prefix, course: course, note: note, limit: limit)
    }

    public func excerpt(note: NoteID, heading: String?) async throws -> NoteExcerpt {
        try await engine.excerpt(note: note, heading: heading)
    }
}
