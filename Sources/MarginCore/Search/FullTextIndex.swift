import Foundation

/// A note as the full-text index sees it. `id` is opaque to the index (the engine uses the path).
public struct FullTextDocument: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// Other names of the note (`aliases:`); searched like the title.
    public var aliases: [String]
    public var headings: [String]
    public var tags: [String]
    public var body: String

    public init(id: String, title: String, aliases: [String] = [], headings: [String] = [],
                tags: [String] = [], body: String = "") {
        self.id = id; self.title = title; self.aliases = aliases; self.headings = headings
        self.tags = tags; self.body = body
    }
}

/// A parsed search query: folded words that must all occur, the last one optionally as a prefix
/// (the user is still typing it).
public struct FullTextQuery: Sendable, Hashable {
    public var terms: [String]
    public var lastIsPrefix: Bool

    public var isEmpty: Bool { terms.isEmpty }

    public init(terms: [String], lastIsPrefix: Bool = true) {
        self.terms = terms; self.lastIsPrefix = lastIsPrefix
    }

    /// `"cell bio"` -> `[cell, bio*]`; a trailing space (`"cell "`) makes the last word exact.
    public init(_ text: String) {
        terms = SearchTokenizer.terms(in: text)
        lastIsPrefix = !(text.last.map { $0.isWhitespace } ?? true)
    }
}

/// One matching document with its relevance (higher is better; only comparable within a query).
public struct FullTextMatch: Sendable, Hashable {
    public var id: String
    public var score: Double
    public init(id: String, score: Double) { self.id = id; self.score = score }
}

/// Full-text search over notes (M10-01): words (diacritics and case folded), prefix queries on the
/// last word, BM25 ranking with the title counting most, then headings, tags and body.
///
/// Implementations: `InMemoryFullTextIndex` (portable, the one every platform can run and test) and
/// `SQLiteFullTextIndex` (FTS5 in `.margin/index.sqlite`, where SQLite3 is available). The index is
/// a cache: it is rebuilt from the notes whenever it is empty or its schema version differs.
public protocol FullTextIndex: Sendable {
    var count: Int { get }
    func contains(id: String) -> Bool
    /// Adds the document or replaces the one with the same id.
    func upsert(_ document: FullTextDocument)
    func remove(id: String)
    func removeAll()
    /// Documents that contain every query word, best first (ties by id). `allowing` filters
    /// before `limit` is applied.
    func search(_ query: FullTextQuery, limit: Int, allowing: (@Sendable (String) -> Bool)?) -> [FullTextMatch]
}

extension FullTextIndex {
    public func search(_ query: FullTextQuery, limit: Int = 50) -> [FullTextMatch] {
        search(query, limit: limit, allowing: nil)
    }

    public func search(_ text: String, limit: Int = 50) -> [FullTextMatch] {
        search(FullTextQuery(text), limit: limit, allowing: nil)
    }
}
