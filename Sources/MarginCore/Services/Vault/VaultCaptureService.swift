/// `CaptureService` over a vault: inbox files, task lines in `<course>/Tasks.md` and new notes,
/// all written atomically through `VaultStore` (rules in `CaptureService`).
public struct VaultCaptureService: CaptureService {
    let backend: VaultBackend

    init(backend: VaultBackend) { self.backend = backend }

    public func parse(_ input: String) async throws -> CaptureDraft { await backend.captureParse(input) }

    public func commit(_ draft: CaptureDraft, actor: Actor, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await backend.captureCommit(draft, actor: actor, dryRun: dryRun, idempotencyKey: idempotencyKey)
    }
}
