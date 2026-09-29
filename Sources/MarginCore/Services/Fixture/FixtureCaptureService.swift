/// `CaptureService` over `Fixtures.week5`, in memory. Writes change the in-memory state only.
public struct FixtureCaptureService: CaptureService {
    let store: FixtureStore

    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.store = FixtureStore(world: world, clock: clock)
    }

    init(store: FixtureStore) { self.store = store }

    public func parse(_ input: String) async throws -> CaptureDraft { await store.captureParse(input) }

    public func commit(_ draft: CaptureDraft, actor: Actor, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await store.captureCommit(draft, actor: actor, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }
}
