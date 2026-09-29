/// Hook called by `VaultStore` after a file or folder was renamed or moved successfully.
///
/// This is where wikilink rewriting plugs in (spec 05 §1: renaming updates links across the
/// vault). The observer receives the store so it can `list`, `read` and `write` (with
/// `expectedVersion`) the notes that need rewriting; those calls are ordinary actor calls, so the
/// store is not blocked while the observer works. The rename itself is already complete and is
/// never rolled back; an observer must handle its own errors.
public protocol RenameObserver: Sendable {
    func vaultDidRename(from: VaultPath, to: VaultPath, isDirectory: Bool, in store: VaultStore) async
}
