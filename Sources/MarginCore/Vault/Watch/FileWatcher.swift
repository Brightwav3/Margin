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
