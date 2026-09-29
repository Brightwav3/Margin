/// `IndexStatus` for the in-memory world: the index is "built" from the start, so every stream gives
/// 100 % at once and ends.
public struct FixtureIndexStatus: IndexStatus {
    private let total: Int

    /// - Parameter noteCount: how many notes the world has (for `filesTotal`).
    public init(noteCount: Int) { total = noteCount }

    init() { total = Fixtures.week5.allNotes.count }

    public var progress: AsyncStream<IndexProgress> {
        IndexProgressTracker(complete: total).subscribe()
    }
}
