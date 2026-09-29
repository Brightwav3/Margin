import Foundation

/// One saved version of a note (`HistoryService`). The text is read with `HistoryService.text(of:)`.
public struct NoteVersion: Codable, Sendable, Hashable, Identifiable {
    /// `<noteID>@<milliseconds since 1970, 13 digits>`; unique and sorts by time within a note.
    public let id: String
    public let noteID: NoteID
    /// When the snapshot was taken (the `Clock`'s `now`).
    public let timestamp: Date
    /// Size of the note text in UTF-8 bytes.
    public let byteCount: Int

    public init(id: String, noteID: NoteID, timestamp: Date, byteCount: Int) {
        self.id = id; self.noteID = noteID; self.timestamp = timestamp; self.byteCount = byteCount
    }
}

/// Why a snapshot is asked for (`HistoryService.snapshot`).
public enum SnapshotReason: String, Codable, Sendable, Hashable {
    /// After a save: taken at most once per 5 minutes.
    case save
    /// The note is being closed: taken whenever the text differs from the newest version.
    case close
}

/// One line of a `NoteDiff`.
public struct DiffLine: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable { case equal, added, removed }
    public var kind: Kind
    /// The line without its line break.
    public var text: String
    /// 1-based line number in the old text (`nil` for an added line).
    public var oldLine: Int?
    /// 1-based line number in the new text (`nil` for a removed line).
    public var newLine: Int?

    public init(kind: Kind, text: String, oldLine: Int?, newLine: Int?) {
        self.kind = kind; self.text = text; self.oldLine = oldLine; self.newLine = newLine
    }
}

/// A line diff from an older text to a newer one: every line of both texts appears once, in order.
public struct NoteDiff: Codable, Sendable, Hashable {
    public var lines: [DiffLine]

    public init(lines: [DiffLine]) { self.lines = lines }

    public var addedCount: Int { lines.filter { $0.kind == .added }.count }
    public var removedCount: Int { lines.filter { $0.kind == .removed }.count }
    /// `true` when both texts are the same.
    public var isIdentical: Bool { !lines.contains { $0.kind != .equal } }
}
