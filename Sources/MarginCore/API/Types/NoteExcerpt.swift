/// The hover preview of a note or of one of its sections (M10-05): plain text, short.
public struct NoteExcerpt: Codable, Sendable, Hashable {
    /// Plain text: no frontmatter, no markdown markers. Empty for a note without prose.
    public var text: String
    /// The heading the excerpt was taken from; `nil` for the start of the note (also when the
    /// requested heading does not exist).
    public var heading: String?
    /// `true` when the paragraph was cut to fit the length limit (`text` then ends with `…`).
    public var isTruncated: Bool

    public var isEmpty: Bool { text.isEmpty }

    public init(text: String, heading: String? = nil, isTruncated: Bool = false) {
        self.text = text; self.heading = heading; self.isTruncated = isTruncated
    }
}
