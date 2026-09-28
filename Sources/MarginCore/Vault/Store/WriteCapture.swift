import Foundation

/// A change the `VaultStore` is about to make, announced to the active `WriteCapture` BEFORE the
/// file system is touched (write-ahead), so a recorder can persist what is needed to reverse it.
enum CapturedOperation: Sendable, Hashable {
    /// Replaces (`before != nil`) or creates (`before == nil`) a file.
    case write(path: VaultPath, before: Data?, after: Data)
    /// Renames or moves a file or folder.
    case move(from: VaultPath, to: VaultPath)
    /// Moves a file or folder to the trash. `before` holds the bytes of a regular file; folders and
    /// other items are not captured (`before == nil`).
    case trash(path: VaultPath, before: Data?, isRegularFile: Bool)
}

/// Receives the operations of the task it is installed for. If `willApply` throws, the store
/// aborts the operation without touching the file system (the write-ahead record could not be
/// made, so the operation must not happen).
protocol WriteCapture: Sendable {
    func willApply(_ operation: CapturedOperation) async throws
}

enum WriteCaptureContext {
    /// The capture that records the store operations made by the current task (and the child tasks
    /// and actor calls made on its behalf, e.g. the link rewriting a rename triggers). Task-local,
    /// so writes by unrelated tasks are never attributed to a transaction.
    @TaskLocal static var current: (any WriteCapture)?
}
