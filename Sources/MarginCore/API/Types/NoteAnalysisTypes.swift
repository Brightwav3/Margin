/// A heading of a note (`## Title`), for the outline in the editor and the inspector.
///
/// `line` is 1-based within `Note.text` (the body, without frontmatter).
public struct OutlineItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(line)" }
    /// 1...6.
    public var level: Int
    public var text: String
    public var line: Int

    public init(level: Int, text: String, line: Int) {
        self.level = level; self.text = text; self.line = line
    }
}

/// A link to a note from another note, with the line it stands on as context.
///
/// `line` is 1-based within the source note's `Note.text`; `context` is that line, trimmed and
/// cut to 160 characters.
public struct NoteBacklink: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(sourceNoteID)#\(line)" }
    public var sourceNoteID: NoteID
    public var sourceTitle: String
    public var line: Int
    public var context: String

    public init(sourceNoteID: NoteID, sourceTitle: String, line: Int, context: String) {
        self.sourceNoteID = sourceNoteID; self.sourceTitle = sourceTitle; self.line = line; self.context = context
    }
}

/// A `[[wikilink]]` in a note and what it points at.
///
/// Links to notes that do not exist yet are included (`state == .notCreated`); the UI shows them as
/// "Not created yet". `line` is 1-based within `Note.text`.
public struct OutgoingLink: Codable, Sendable, Hashable, Identifiable {
    public enum State: String, Codable, Sendable, Hashable {
        /// Exactly one note matches (`noteID` is set).
        case resolved
        /// Several equally good notes match (`candidates`, sorted).
        case ambiguous
        /// No such note yet.
        case notCreated
        /// `[[#Heading]]`: a link inside the same note.
        case selfLink
    }

    public var id: String { "\(line)#\(target)#\(heading ?? "")" }
    /// Note part as written, without heading or alias (`Cell Biology`, `Folder/Note`); empty for `[[#Heading]]`.
    public var target: String
    public var heading: String?
    public var alias: String?
    public var isEmbed: Bool
    public var line: Int
    public var state: State
    /// The target note when `state == .resolved`.
    public var noteID: NoteID?
    /// Title of the target note when `state == .resolved`.
    public var title: String?
    /// The candidates when `state == .ambiguous`.
    public var candidates: [NoteID]

    public init(target: String, heading: String? = nil, alias: String? = nil, isEmbed: Bool = false, line: Int,
                state: State, noteID: NoteID? = nil, title: String? = nil, candidates: [NoteID] = []) {
        self.target = target; self.heading = heading; self.alias = alias; self.isEmbed = isEmbed
        self.line = line; self.state = state; self.noteID = noteID; self.title = title; self.candidates = candidates
    }
}

/// Numbers shown in the note inspector: `backlinks` notes-linking-here count (one per link),
/// `properties` frontmatter keys, `words` in the body, `openTasks` of `totalTasks`.
public struct NoteStats: Codable, Sendable, Hashable {
    public var backlinks: Int
    public var properties: Int
    public var words: Int
    public var openTasks: Int
    public var totalTasks: Int

    public init(backlinks: Int = 0, properties: Int = 0, words: Int = 0, openTasks: Int = 0, totalTasks: Int = 0) {
        self.backlinks = backlinks; self.properties = properties; self.words = words
        self.openTasks = openTasks; self.totalTasks = totalTasks
    }
}
