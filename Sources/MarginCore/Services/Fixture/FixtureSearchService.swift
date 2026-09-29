/// `SearchService` over `Fixtures.week5`, in memory: the same engine as `VaultSearchService`,
/// fed with the fixture notes (writes to the fixture show up in later searches).
public struct FixtureSearchService: SearchService {
    private let engine: SearchEngine

    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.init(store: FixtureStore(world: world, clock: clock))
    }

    init(store: FixtureStore) {
        engine = SearchEngine(provider: { await store.searchSources() })
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
