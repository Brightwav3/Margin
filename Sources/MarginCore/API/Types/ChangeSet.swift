import Foundation

/// The result of a write: which files changed, who did it and when (contract rule 0).
///
/// A dry run (`isDryRun`) returns the `ChangeSet` the write *would* produce and changes nothing.
/// Hashes are lower-case hex SHA-256 of the exact file bytes, so `afterHash` of a note write equals
/// `Note.version` afterwards and `beforeHash` is the `baseVersion` that was current.
///
/// AG-03 extends this with the inverse (undo) data; new fields must be optional.
public struct ChangeSet: Codable, Sendable, Hashable, Identifiable {
    /// One file touched by the write.
    public struct Entry: Codable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable, Hashable {
            case created, modified, deleted
            /// Renamed or moved: `path` is the new location, `fromPath` the old one.
            case moved
        }

        /// Vault-relative path (`/`-separated), or a synthetic path in the fixture implementation.
        public var path: String
        public var kind: Kind
        /// The note this entry belongs to, when it is a note.
        public var noteID: NoteID?
        /// Old path of a `.moved` entry.
        public var fromPath: String?
        /// Hash before the write; `nil` for `.created`.
        public var beforeHash: String?
        /// Hash after the write; `nil` for `.deleted`.
        public var afterHash: String?

        public init(path: String, kind: Kind, noteID: NoteID? = nil, fromPath: String? = nil,
                    beforeHash: String? = nil, afterHash: String? = nil) {
            self.path = path; self.kind = kind; self.noteID = noteID; self.fromPath = fromPath
            self.beforeHash = beforeHash; self.afterHash = afterHash
        }
    }

    public let id: String
    public var actor: Actor
    /// When the write happened (from the `Clock`).
    public var timestamp: Date
    public var entries: [Entry]
    public var isDryRun: Bool
    /// The key the caller sent, if any.
    public var idempotencyKey: String?

    public init(id: String, actor: Actor, timestamp: Date, entries: [Entry], isDryRun: Bool = false,
                idempotencyKey: String? = nil) {
        self.id = id; self.actor = actor; self.timestamp = timestamp; self.entries = entries
        self.isDryRun = isDryRun; self.idempotencyKey = idempotencyKey
    }

    /// `true` when the write changed nothing (for example saving identical text).
    public var isEmpty: Bool { entries.isEmpty }
}
