import Foundation

/// One file-level operation of a recorded write, with what is needed to reverse it. Written to
/// `.margin/changesets/<record>.op-NNNN.json` BEFORE the operation is applied (write-ahead).
///
/// File contents are embedded as base64 (JSON `Data`), so undo restores the exact bytes: BOM,
/// CRLF, invalid text and all.
struct RecordedOperation: Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, Hashable {
        /// A file was replaced: `before` and `after` are its bytes.
        case write
        /// A file was created: `after` is its bytes.
        case create
        /// A file or folder was renamed or moved from `fromPath` to `path`.
        case move
        /// A file or folder was moved to the trash: `before` is the file's bytes.
        case trash
    }

    var kind: Kind
    /// Vault-relative path acted on (the new path of a move).
    var path: String
    var fromPath: String?
    var before: Data?
    var after: Data?
    var beforeHash: String?
    var afterHash: String?
    /// `false` for a trashed folder or non-regular item: its content was not captured, so it
    /// cannot be restored by undo (nothing is lost, it is in the trash).
    var restorable: Bool?

    init(kind: Kind, path: String, fromPath: String? = nil, before: Data? = nil, after: Data? = nil,
         restorable: Bool? = nil) {
        self.kind = kind; self.path = path; self.fromPath = fromPath
        self.before = before; self.after = after
        self.beforeHash = before.map { ContentHash(of: $0).hex }
        self.afterHash = after.map { ContentHash(of: $0).hex }
        self.restorable = restorable
    }

    init(_ operation: CapturedOperation) {
        switch operation {
        case .write(let path, let before, let after):
            self.init(kind: before == nil ? .create : .write, path: path.rawValue, before: before, after: after)
        case .move(let from, let to):
            self.init(kind: .move, path: to.rawValue, fromPath: from.rawValue)
        case .trash(let path, let before, let isRegularFile):
            self.init(kind: .trash, path: path.rawValue, before: before, restorable: isRegularFile ? nil : false)
        }
    }

    /// The change-set entry that describes this operation (used for files the caller did not
    /// describe itself, such as notes whose links were rewritten by a move).
    func derivedEntry(noteID: NoteID?) -> ChangeSet.Entry {
        switch kind {
        case .write: .init(path: path, kind: .modified, noteID: noteID, beforeHash: beforeHash, afterHash: afterHash)
        case .create: .init(path: path, kind: .created, noteID: noteID, afterHash: afterHash)
        case .move: .init(path: path, kind: .moved, noteID: noteID, fromPath: fromPath)
        case .trash: .init(path: path, kind: .deleted, noteID: noteID, beforeHash: beforeHash)
        }
    }
}

/// The small committed record: written last, atomically. Its presence is the commit point; op
/// files without it belong to an interrupted transaction and are rolled back on open.
struct CommittedRecord: Codable, Sendable {
    var format: Int
    var changeSet: ChangeSet
    var operationCount: Int
}
