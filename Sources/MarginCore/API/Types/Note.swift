/// Kind of a note (`type:` in frontmatter).
public enum NoteKind: String, Codable, Sendable, Hashable, CaseIterable {
    case lecture, lab, seminar, tutorial, study, note
}

/// Lightweight description of a note for lists and cards (no body).
///
/// Invariants: `openTasks <= totalTasks`; `title` equals the `# H1`/file name.
/// `isPlaceholder` marks a note created from the timetable that has no content yet.
public struct NoteSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: NoteID
    public var courseID: CourseID?
    public var title: String
    public var kind: NoteKind
    /// Date of the class the note belongs to (`date:` frontmatter), if any.
    public var date: LocalDate?
    /// First lines of text, plain.
    public var snippet: String
    public var wordCount: Int
    public var openTasks: Int
    public var totalTasks: Int
    public var imageCount: Int
    public var isPlaceholder: Bool
    public var modified: LocalDateTime?

    public init(
        id: NoteID, courseID: CourseID? = nil, title: String, kind: NoteKind = .note,
        date: LocalDate? = nil, snippet: String = "", wordCount: Int = 0,
        openTasks: Int = 0, totalTasks: Int = 0, imageCount: Int = 0,
        isPlaceholder: Bool = false, modified: LocalDateTime? = nil
    ) {
        self.id = id; self.courseID = courseID; self.title = title; self.kind = kind
        self.date = date; self.snippet = snippet; self.wordCount = wordCount
        self.openTasks = openTasks; self.totalTasks = totalTasks; self.imageCount = imageCount
        self.isPlaceholder = isPlaceholder; self.modified = modified
    }
}

/// A full note: summary plus markdown text.
///
/// `version` is the opaque token used as `baseVersion` for optimistic writes; it changes on
/// every save.
public struct Note: Codable, Sendable, Hashable, Identifiable {
    public var id: NoteID { summary.id }
    public var summary: NoteSummary
    /// Markdown body (without frontmatter).
    public var text: String
    public var version: String

    public init(summary: NoteSummary, text: String, version: String = "1") {
        self.summary = summary; self.text = text; self.version = version
    }
}
