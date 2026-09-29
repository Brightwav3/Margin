import Foundation

/// The typed error crossing the backend/UI boundary (contract rule 6). The UI maps each case to
/// a banner or toast. Every case carries a human-readable message (English, for logs and agents).
///
/// Encoded as `{"code": "notFound", "message": "…"}` so agents and the CLI get a stable shape.
public enum MarginError: Error, Sendable, Hashable, Equatable {
    /// Disk or system failure (read/write/atomic rename).
    case io(String)
    /// `baseVersion` no longer matches the stored version (or the target is taken, or an undo would
    /// overwrite later changes); the caller must re-read and merge. The optional `ConflictDetail`
    /// carries the current version and, for notes, a merge result with conflict markers.
    case conflict(String, ConflictDetail? = nil)
    /// The referenced course, note, task or file does not exist.
    case notFound(String)
    /// The input violates an invariant (bad date, unknown key, malformed frontmatter).
    case invalid(String)
    /// The target is read-only (archived semester, locked note).
    case readOnly(String)
    /// The actor's identity/profile does not allow the operation.
    case forbidden(String)
    /// The actor exceeded its limits; retry later.
    case rateLimited(String)

    /// Stable machine-readable code.
    public var code: String {
        switch self {
        case .io: "io"
        case .conflict: "conflict"
        case .notFound: "notFound"
        case .invalid: "invalid"
        case .readOnly: "readOnly"
        case .forbidden: "forbidden"
        case .rateLimited: "rateLimited"
        }
    }

    /// The message payload.
    public var message: String {
        switch self {
        case .conflict(let m, _):
            m
        case .io(let m), .notFound(let m), .invalid(let m),
             .readOnly(let m), .forbidden(let m), .rateLimited(let m):
            m
        }
    }

    /// The machine-readable part of a `.conflict` (`nil` for every other error, and for conflicts
    /// that carry none, such as a taken title).
    public var conflictDetail: ConflictDetail? {
        if case .conflict(_, let detail) = self { return detail }
        return nil
    }
}

/// What a caller needs to resolve a `.conflict` without another round trip.
///
/// Encoded inside the error as `"detail": {…}`; every field is optional and absent ones are
/// omitted, so older readers of the error keep working.
public struct ConflictDetail: Codable, Sendable, Hashable {
    /// Vault-relative path (or synthetic path in the fixture implementation) of the contested file.
    public var path: String?
    /// The version that is stored now: pass it as `baseVersion` after merging.
    public var currentVersion: String?
    /// For a note body: the three-way merge of the caller's text and the stored text, with
    /// `<<<<<<<` / `=======` / `>>>>>>>` markers around every region changed differently on both
    /// sides. `nil` when no merge was possible (the base text is unknown, or the conflict is not
    /// about note text).
    public var mergedText: String?
    /// Number of marker regions in `mergedText`.
    public var conflictCount: Int?

    public init(path: String? = nil, currentVersion: String? = nil, mergedText: String? = nil,
                conflictCount: Int? = nil) {
        self.path = path; self.currentVersion = currentVersion
        self.mergedText = mergedText; self.conflictCount = conflictCount
    }
}

extension MarginError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { "\(code): \(message)" }
    public var description: String { "\(code): \(message)" }
}

extension MarginError: Codable {
    private enum CodingKeys: String, CodingKey { case code, message, detail }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let code = try c.decode(String.self, forKey: .code)
        let message = try c.decode(String.self, forKey: .message)
        switch code {
        case "io": self = .io(message)
        case "conflict": self = .conflict(message, try c.decodeIfPresent(ConflictDetail.self, forKey: .detail))
        case "notFound": self = .notFound(message)
        case "invalid": self = .invalid(message)
        case "readOnly": self = .readOnly(message)
        case "forbidden": self = .forbidden(message)
        case "rateLimited": self = .rateLimited(message)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .code, in: c, debugDescription: "Unknown error code '\(code)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(message, forKey: .message)
        try c.encodeIfPresent(conflictDetail, forKey: .detail)
    }
}
