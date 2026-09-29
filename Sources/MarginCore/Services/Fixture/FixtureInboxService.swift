/// `InboxService` over the five inbox items of `Fixtures.week5`, in memory.
public struct FixtureInboxService: InboxService {
    let store: FixtureStore

    public init(world: FixtureWorld = Fixtures.week5, clock: any Clock = FixedClock()) {
        self.store = FixtureStore(world: world, clock: clock)
    }

    init(store: FixtureStore) { self.store = store }

    public func items() async throws -> [InboxItem] { await store.inboxItems() }

    public func triage(item: String, course: CourseID, when: LocalDate?, kind: InboxKind?, actor: Actor,
                       baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await store.inboxTriage(item: item, course: course, when: when, kind: kind, actor: actor,
                                    baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func delete(item: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await store.inboxDelete(item: item, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                    idempotencyKey: idempotencyKey)
    }
}
