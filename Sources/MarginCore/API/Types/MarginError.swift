import Foundation

/// The typed error crossing the backend/UI boundary (contract rule 6). The UI maps each case to
/// a banner or toast. Every case carries a human-readable message (English, for logs and agents).
///
/// Encoded as `{"code": "notFound", "message": "…"}` so agents and the CLI get a stable shape.
public enum MarginError: Error, Sendable, Hashable, Equatable {
    /// Disk or system failure (read/write/atomic rename).
    case io(String)
    /// `baseVersion` no longer matches the stored version; the caller must re-read and merge.
    case conflict(String)
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
        case .io(let m), .conflict(let m), .notFound(let m), .invalid(let m),
             .readOnly(let m), .forbidden(let m), .rateLimited(let m):
            m
        }
    }
}

extension MarginError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { "\(code): \(message)" }
    public var description: String { "\(code): \(message)" }
}

extension MarginError: Codable {
    private enum CodingKeys: String, CodingKey { case code, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let code = try c.decode(String.self, forKey: .code)
        let message = try c.decode(String.self, forKey: .message)
        switch code {
        case "io": self = .io(message)
        case "conflict": self = .conflict(message)
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
    }
}
