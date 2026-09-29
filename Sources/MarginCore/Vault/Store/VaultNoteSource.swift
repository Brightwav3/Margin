/// Feeds a `NoteIndex` from a `VaultStore`: the bridge between the store and the index.
public struct VaultNoteSource: NoteContentSource {
    public let store: VaultStore

    public init(store: VaultStore) { self.store = store }

    public func listMarkdown() async throws -> [String] {
        try await store.list().map(\.rawValue)
    }

    public func read(_ path: String) async throws -> String {
        try await store.read(VaultPath(path)).content
    }
}
