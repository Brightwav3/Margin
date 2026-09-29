/// A range of characters in a string (`Character` offsets, not UTF-16), for highlighting.
public struct HighlightRange: Codable, Sendable, Hashable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) { self.location = location; self.length = length }
}

/// Narrows a search. Every field is optional; the set fields must all hold.
///
/// - `course`: notes of that course.
/// - `kind`: notes of that `type:`.
/// - `from`/`to`: notes whose `date:` lies in the range, both ends included; an undated note
///   never matches a date bound.
/// - `tags`: the note has every one of these tags (case-insensitive, a leading `#` is ignored).
/// - `limit`: at most this many hits (at least 1).
public struct SearchFilter: Codable, Sendable, Hashable {
    public var course: CourseID?
    public var kind: NoteKind?
    public var from: LocalDate?
    public var to: LocalDate?
    public var tags: [String]
    public var limit: Int

    public static let defaultLimit = 50

    /// No restriction.
    public static let none = SearchFilter()

    public init(course: CourseID? = nil, kind: NoteKind? = nil, from: LocalDate? = nil, to: LocalDate? = nil,
                tags: [String] = [], limit: Int = SearchFilter.defaultLimit) {
        self.course = course; self.kind = kind; self.from = from; self.to = to
        self.tags = tags; self.limit = limit
    }

    /// `true` when nothing but `limit` is set.
    public var restrictsNothing: Bool {
        course == nil && kind == nil && from == nil && to == nil && tags.isEmpty
    }
}

/// One result of `SearchService.search`.
public struct SearchHit: Codable, Sendable, Hashable, Identifiable {
    /// The note id (`NoteRepository.open(id:)`).
    public var id: NoteID
    public var title: String
    public var courseID: CourseID?
    public var kind: NoteKind
    public var date: LocalDate?
    /// A passage of the note around the first match, plain text on one line, about 140 characters;
    /// `…` marks where it was cut. For a note that matches only by title, heading or tag: its
    /// first lines.
    public var snippet: String
    /// Where the query words stand in `snippet`.
    public var highlights: [HighlightRange]
    /// Where the query words stand in `title`.
    public var titleHighlights: [HighlightRange]
    /// Relevance (BM25); only comparable within one result list. `0` for a search without words.
    public var score: Double

    public init(id: NoteID, title: String, courseID: CourseID? = nil, kind: NoteKind = .note,
                date: LocalDate? = nil, snippet: String = "", highlights: [HighlightRange] = [],
                titleHighlights: [HighlightRange] = [], score: Double = 0) {
        self.id = id; self.title = title; self.courseID = courseID; self.kind = kind; self.date = date
        self.snippet = snippet; self.highlights = highlights; self.titleHighlights = titleHighlights
        self.score = score
    }
}
