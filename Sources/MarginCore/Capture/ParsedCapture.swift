/// What a highlighted part of the capture line means. The UI maps kinds to chips.
public enum CaptureSpanKind: String, Codable, Sendable, Hashable, CaseIterable {
    case course, date, tag, attachment, url
    /// A leading `note:` / `task:` / `link:` marker.
    case kindPrefix
}

/// A detected part of the input, for chip highlighting.
///
/// `range` counts `Character`s (extended grapheme clusters) of the original input, not UTF-16
/// units, so it can be turned into a `String.Index` range with `range(in:)`.
public struct CaptureSpan: Codable, Sendable, Hashable {
    public var kind: CaptureSpanKind
    public var range: Range<Int>

    public init(kind: CaptureSpanKind, range: Range<Int>) {
        self.kind = kind; self.range = range
    }

    /// The same range as `String.Index` bounds of `text`; `nil` when it does not fit `text`.
    public func range(in text: String) -> Range<String.Index>? {
        guard range.lowerBound >= 0, range.upperBound <= text.count else { return nil }
        let lo = text.index(text.startIndex, offsetBy: range.lowerBound)
        let hi = text.index(lo, offsetBy: range.count)
        return lo..<hi
    }
}

/// "to lecture 8" / "for lecture": the capture should be appended to a lecture note.
public struct CaptureLectureHint: Codable, Sendable, Hashable {
    /// Lecture number when the input names one (`lecture 8`); `nil` for a bare "lecture".
    public var number: Int?

    public init(number: Int? = nil) { self.number = number }
}

/// Result of `QuickCaptureParser.parse`: the API draft plus what the UI needs to render chips.
public struct ParsedCapture: Codable, Sendable, Hashable {
    /// The draft to commit. `text` has explicit markup (`#tags`, `@due`, `note:`) removed;
    /// natural-language dates and course names stay in it.
    public var draft: CaptureDraft
    /// Detected parts of the original input, sorted by position, never overlapping.
    public var spans: [CaptureSpan]
    /// Time of day written next to the date (`friday 5pm`); `LocalDate` due has no time part.
    public var dueTime: LocalTime?
    /// Set when the input asks to attach to a lecture note, whether or not a note was resolved.
    public var lectureHint: CaptureLectureHint?

    public init(draft: CaptureDraft, spans: [CaptureSpan] = [], dueTime: LocalTime? = nil,
                lectureHint: CaptureLectureHint? = nil) {
        self.draft = draft; self.spans = spans; self.dueTime = dueTime; self.lectureHint = lectureHint
    }
}
