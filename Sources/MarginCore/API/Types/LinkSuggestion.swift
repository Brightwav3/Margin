/// One entry of the `[[` popup (M10-03).
public struct LinkSuggestion: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        /// A note matched by its title or file name.
        case note
        /// A note matched by one of its `aliases:`; inserts `Name|alias`.
        case alias
        /// A heading of a note (or of the current note); inserts `Name#Heading`.
        case heading
        /// "Create <text>": no note has this name yet.
        case create
    }

    public var id: String
    public var kind: Kind
    /// What the row shows: the note title, the alias, the heading or the text to create.
    public var title: String
    /// What goes between `[[` and `]]`.
    public var insertText: String
    /// The note the entry points at; `nil` for `.create`.
    public var noteID: NoteID?
    public var courseID: CourseID?
    /// Second line of the row: the note title for an alias or heading.
    public var detail: String?

    public init(id: String, kind: Kind, title: String, insertText: String, noteID: NoteID? = nil,
                courseID: CourseID? = nil, detail: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.insertText = insertText
        self.noteID = noteID; self.courseID = courseID; self.detail = detail
    }
}
