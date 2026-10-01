/// How far building the note index has come (M11-07.B).
///
/// `percent` runs 0…100 and reaches 100 only when the index is complete (`isComplete`), so a screen
/// can show a progress bar and drop it on 100.
public struct IndexProgress: Codable, Sendable, Hashable {
    /// Notes read so far.
    public let filesDone: Int
    /// Notes to read in all (known once the vault was listed; 0 before).
    public let filesTotal: Int
    /// The index is built and ready for queries.
    public let isComplete: Bool

    public init(filesDone: Int, filesTotal: Int, isComplete: Bool = false) {
        self.filesTotal = max(0, filesTotal)
        self.filesDone = min(max(0, filesDone), self.filesTotal)
        self.isComplete = isComplete
    }

    /// Whole percent, 0…100. Below 100 until `isComplete`.
    public var percent: Int {
        if isComplete { return 100 }
        guard filesTotal > 0 else { return 0 }
        return min(99, filesDone * 100 / filesTotal)
    }
}

/// Progress of building the index (loading screen, mockup 2c). Implementations: `FixtureIndexStatus`
/// and `VaultIndexStatus`. Rules both obey, checked by
/// `Tests/Conformance/IndexStatusConformanceTests.swift`:
///
/// - **Replay:** a stream starts with the current state, so subscribing late (after the index is
///   built) still gives the finished state, and every stream ends with a complete element.
/// - **Monotonic:** `percent` never decreases; each value is reported once (at most 101 elements),
///   from at most 0 to exactly 100.
/// - **Completion:** the last element has `isComplete` and `percent == 100`, then the stream ends.
///   An empty vault is complete at once.
/// - The fixture is complete from the start (100 % immediately).
///
/// `AppEnvironment.vault(at:)` returns once the index is built; to show progress while it builds, pass
/// its `progress` callback, which reports the same elements.
public protocol IndexStatus: Sendable {
    /// The state now, every change after it, and the end of the stream once complete.
    var progress: AsyncStream<IndexProgress> { get }

    /// What the vault holds on disk now (Settings › Vault and files): Markdown notes, other files
    /// (attachments) and the version history. Hidden files and `.margin/` (except history) do not count.
    func vaultStats() async throws -> VaultStats
}

/// Sizes of a vault (`IndexStatus.vaultStats`). Bytes are file sizes on disk.
public struct VaultStats: Codable, Sendable, Hashable {
    public var noteCount: Int
    public var noteBytes: Int64
    public var attachmentCount: Int
    public var attachmentBytes: Int64
    public var historyBytes: Int64

    public init(noteCount: Int, noteBytes: Int64, attachmentCount: Int, attachmentBytes: Int64, historyBytes: Int64) {
        self.noteCount = noteCount; self.noteBytes = noteBytes; self.attachmentCount = attachmentCount
        self.attachmentBytes = attachmentBytes; self.historyBytes = historyBytes
    }
}
