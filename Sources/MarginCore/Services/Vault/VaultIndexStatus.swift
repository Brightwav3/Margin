/// `IndexStatus` over a vault: the progress of the build `VaultBackend.open` did. It is complete when
/// the environment exists; the stream is for late subscribers and for the `progress` callback of
/// `AppEnvironment.vault(at:)`, which sees every step.
public struct VaultIndexStatus: IndexStatus {
    let tracker: IndexProgressTracker
    let store: VaultStore

    init(backend: VaultBackend) { tracker = backend.indexProgress; store = backend.store }

    public var progress: AsyncStream<IndexProgress> { tracker.subscribe() }

    public func vaultStats() async throws -> VaultStats { try await store.usage() }
}
