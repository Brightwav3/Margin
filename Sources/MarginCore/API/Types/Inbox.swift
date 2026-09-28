/// What an inbox entry or capture is.
public enum InboxKind: String, Codable, Sendable, Hashable, CaseIterable {
    case task, note, link, image
}

/// How it reached the inbox (`source:` frontmatter).
public enum InboxSource: String, Codable, Sendable, Hashable, CaseIterable {
    case phone
    case quickCapture = "quick-capture"
    case share
}

/// An unsorted capture in `_inbox/`. Invariant: `text` is non-empty.
public struct InboxItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var text: String
    public var kind: InboxKind
    public var source: InboxSource
    public var captured: LocalDateTime

    public init(id: String, text: String, kind: InboxKind, source: InboxSource, captured: LocalDateTime) {
        self.id = id; self.text = text; self.kind = kind; self.source = source; self.captured = captured
    }
}

/// Result of parsing a quick-capture line, before it is committed.
public struct CaptureDraft: Codable, Sendable, Hashable {
    public var text: String
    public var course: CourseID?
    public var due: LocalDate?
    public var tags: [String]
    public var kind: InboxKind
    /// Note to append to instead of creating a new one.
    public var attachTo: NoteID?

    public init(text: String, course: CourseID? = nil, due: LocalDate? = nil, tags: [String] = [],
                kind: InboxKind = .task, attachTo: NoteID? = nil) {
        self.text = text; self.course = course; self.due = due; self.tags = tags
        self.kind = kind; self.attachTo = attachTo
    }
}
