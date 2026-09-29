/// `InboxService` over a vault: items are the files of `_inbox/` (spec 05 §6); triage and delete
/// write through `VaultStore` and move the inbox file to the trash.
public struct VaultInboxService: InboxService {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func items() async throws -> [InboxItem] { try await backend.inboxItems() }

    public func triage(item: String, course: CourseID, when: LocalDate?, kind: InboxKind?, actor: Actor,
                       baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.inboxTriage(item: item, course: course, when: when, kind: kind, actor: actor,
                                      baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }

    public func delete(item: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.inboxDelete(item: item, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                      idempotencyKey: idempotencyKey)
    }
}
