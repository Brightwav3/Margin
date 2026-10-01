/// `IndexStatus` for the in-memory world: the index is "built" from the start, so every stream gives
/// 100 % at once and ends.
public struct FixtureIndexStatus: IndexStatus {
    private let total: Int
    private let store: FixtureStore?

    /// - Parameter noteCount: how many notes the world has (for `filesTotal`).
    public init(noteCount: Int) { total = noteCount; store = nil }

    init(store: FixtureStore? = nil) { total = Fixtures.week5.allNotes.count; self.store = store }

    /// Notes and history of the in-memory world; it has no attachments.
    public func vaultStats() async throws -> VaultStats {
        guard let store else { return VaultStats(noteCount: total, noteBytes: 0, attachmentCount: 0, attachmentBytes: 0, historyBytes: 0) }
        return await store.usage()
    }

    public var progress: AsyncStream<IndexProgress> {
        IndexProgressTracker(complete: total).subscribe()
    }
}
