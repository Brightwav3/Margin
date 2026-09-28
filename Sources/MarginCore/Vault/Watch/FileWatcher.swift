import Foundation

/// One observed change under the vault root. Paths are vault-relative with `/` separators.
/// A rename surfaces as `.deleted` (old path) plus `.created` (new path).
public struct FileChange: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case created, modified, deleted
    }

    public let path: String
    public let kind: Kind

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }
}

/// Watches a vault folder and reports external changes in coalesced batches.
///
/// Only markdown files and files inside `_files/` folders are reported; dotfiles and everything
/// under `.margin/` are ignored. Cancelling the consuming task (or finishing iteration) stops the
/// watcher. Changes the app wrote itself are swallowed via `OwnWriteRegistry`.
public protocol FileWatcher: Sendable {
    /// Starts watching. The baseline snapshot is taken before this returns, so any change made
    /// after the call is reported.
    func changes() -> AsyncStream<[FileChange]>
}

/// Content hash helper (FNV-1a 64, hex). Cheap and dependency-free; not cryptographic.
public enum ContentHash {
    public static func fnv1a(_ data: Data) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in data {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(h, radix: 16)
    }

    /// Hash of a file's bytes, or `nil` when it cannot be read.
    public static func ofFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return fnv1a(data)
    }
}
