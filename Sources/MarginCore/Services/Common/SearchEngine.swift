import Foundation

/// A note handed to the search engine with the course id the service reports for it (the vault
/// maps folders to courses, the fixture takes the id from its notes).
struct SearchSource: Sendable {
    var record: NoteRecord
    var courseID: CourseID?
}

/// The search logic shared by `FixtureSearchService` and `VaultSearchService`: both feed it the
/// notes of their world, it keeps a `FullTextIndex` and a `LinkSuggester` in step with them and
/// answers all three `SearchService` calls. Sharing it is what keeps the two observably identical.
///
/// Every call first compares the notes' content hashes with what is indexed and re-indexes only
/// what changed, so results follow saves and outside edits without any change notification.
actor SearchEngine {
    typealias Provider = @Sendable () async -> [SearchSource]

    private struct Doc: Sendable {
        var source: SearchSource
        var hash: String
        var courseID: CourseID?
        var foldedTags: Set<String>
        /// The text without frontmatter (snippets are cut from it).
        var body: String
    }

    private let provider: Provider
    private let fullText: any FullTextIndex
    private var docs: [String: Doc] = [:]            // by path
    private var pathByID: [NoteID: String] = [:]
    private var suggester = LinkSuggester(targets: [])
    private var suggesterStale = false

    init(provider: @escaping Provider, index: any FullTextIndex = InMemoryFullTextIndex()) {
        self.provider = provider
        self.fullText = index
    }

    // MARK: Sync

    /// Brings the index up to date with the notes; cheap when nothing changed.
    func sync() async {
        let sources = await provider()
        var seen = Set<String>()
        seen.reserveCapacity(sources.count)
        for s in sources {
            let path = s.record.path
            seen.insert(path)
            if let old = docs[path], old.hash == s.record.contentHash, old.courseID == s.courseID { continue }
            index(s)
        }
        for path in docs.keys where !seen.contains(path) {
            fullText.remove(id: path)
            docs[path] = nil
            suggesterStale = true
        }
        if suggesterStale {
            var byID: [NoteID: String] = [:]
            for path in docs.keys.sorted().reversed() { byID[docs[path]!.source.record.id] = path }   // smallest path wins
            pathByID = byID
        }
        if suggesterStale {
            suggester = LinkSuggester(targets: docs.values.map { Self.target(of: $0.source) })
            suggesterStale = false
        }
    }

    private func index(_ s: SearchSource) {
        let r = s.record
        let body = Frontmatter.parse(r.text).body
        fullText.upsert(FullTextDocument(
            id: r.path, title: r.title, aliases: Self.aliases(of: r), headings: r.headings.map(\.text),
            tags: r.tags.map(Self.plainTag), body: body))
        docs[r.path] = Doc(source: s, hash: r.contentHash, courseID: s.courseID,
                           foldedTags: Set(r.tags.map { SearchTokenizer.fold(Self.plainTag($0)) }), body: body)
        suggesterStale = true
    }

    private static func plainTag(_ t: String) -> String { t.hasPrefix("#") ? String(t.dropFirst()) : t }

    /// `aliases:` (or `alias:`) of the frontmatter: a list or a single string.
    static func aliases(of r: NoteRecord) -> [String] {
        var out: [String] = []
        for key in ["aliases", "alias"] {
            switch r.properties[key] {
            case .list(let items): for case .string(let s) in items where !s.isEmpty { out.append(s) }
            case .string(let s)?: if !s.isEmpty { out.append(s) }
            default: break
            }
        }
        return out
    }

    private static func target(of s: SearchSource) -> LinkTarget {
        let r = s.record
        return LinkTarget(id: r.id, courseID: s.courseID, name: r.name, path: NoteIndex.stripExtension(r.path),
                          title: r.title, aliases: aliases(of: r),
                          headings: r.headings.filter { $0.level >= 2 }.map(\.text))
    }

    // MARK: Search

    func search(query text: String, filter: SearchFilter) async throws -> [SearchHit] {
        guard filter.limit >= 1 else { throw MarginError.invalid("Search limit must be at least 1") }
        await sync()
        let query = FullTextQuery(text)
        let wantedTags = Set(filter.tags.map { SearchTokenizer.fold(Self.plainTag($0)) })
        let docs = self.docs
        let passes: @Sendable (String) -> Bool = { path in
            guard let d = docs[path] else { return false }
            return Self.passes(d, filter, wantedTags)
        }

        if query.isEmpty {
            guard !filter.restrictsNothing else { return [] }
            let listed = docs.values.filter { passes($0.source.record.path) }.map(\.source.record).sorted(by: Self.browseOrder)
            return listed.prefix(filter.limit).map { r in
                hit(for: r, snippet: r.snippet, highlights: [], titleHighlights: [], score: 0)
            }
        }

        let matches = fullText.search(query, limit: filter.limit, allowing: passes)
        // The index orders by score; equal scores get the documented tie-break here.
        let ordered = matches.compactMap { m in docs[m.id].map { (m, $0.source.record) } }.sorted {
            if $0.0.score != $1.0.score { return $0.0.score > $1.0.score }
            let (a, b) = ($0.1.title.lowercased(), $1.1.title.lowercased())
            return a != b ? a < b : $0.1.id < $1.1.id
        }
        return ordered.map { m, r in
            let passage = SearchSnippet.passage(of: docs[r.path]?.body ?? "", query: query)
            return hit(for: r, snippet: passage?.text ?? r.snippet, highlights: passage?.highlights ?? [],
                       titleHighlights: SearchSnippet.highlights(in: r.title, query: query), score: m.score)
        }
    }

    private func hit(for r: NoteRecord, snippet: String, highlights: [HighlightRange],
                     titleHighlights: [HighlightRange], score: Double) -> SearchHit {
        SearchHit(id: r.id, title: r.title, courseID: docs[r.path]?.courseID, kind: r.kind, date: r.date,
                  snippet: snippet, highlights: highlights, titleHighlights: titleHighlights, score: score)
    }

    private static func passes(_ d: Doc, _ f: SearchFilter, _ tags: Set<String>) -> Bool {
        let r = d.source.record
        if let c = f.course, d.courseID != c { return false }
        if let k = f.kind, r.kind != k { return false }
        if f.from != nil || f.to != nil {
            guard let date = r.date else { return false }
            if let from = f.from, date < from { return false }
            if let to = f.to, date > to { return false }
        }
        return tags.isSubset(of: d.foldedTags)
    }

    /// Dated notes first, newest date first, then undated; ties by title, then id (the order of
    /// `NoteRepository.notes`).
    private static func browseOrder(_ a: NoteRecord, _ b: NoteRecord) -> Bool {
        switch (a.date, b.date) {
        case let (x?, y?) where x != y: return x > y
        case (.some, .none): return true
        case (.none, .some): return false
        default:
            let (s, t) = (a.title.lowercased(), b.title.lowercased())
            return s != t ? s < t : a.id < b.id
        }
    }

    // MARK: Links and excerpts

    func suggestLinks(prefix: String, course: CourseID?, note: NoteID?, limit: Int) async throws -> [LinkSuggestion] {
        guard limit >= 1 else { throw MarginError.invalid("Suggestion limit must be at least 1") }
        await sync()
        return suggester.suggest(prefix, course: course, note: note, limit: limit)
    }

    func excerpt(note: NoteID, heading: String?) async throws -> NoteExcerpt {
        await sync()
        guard let path = pathByID[note], let doc = docs[path] else { throw MarginError.notFound("No note \(note)") }
        return NoteExcerptProvider.excerpt(of: doc.source.record.text, heading: heading)
    }
}
