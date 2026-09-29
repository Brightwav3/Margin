import Foundation

/// `InboxService` on a vault. The layout rules are in `CaptureRules`, the behaviour in `InboxService`.
extension VaultBackend {
    func inboxItems() async throws -> [InboxItem] {
        // No vault folder is an error to show; no `_inbox` folder (yet) is an empty inbox.
        guard await store.isAvailable() else { throw MarginError.notFound("The vault folder is not available") }
        let listed: [VaultPath]
        do { listed = try await store.list(under: VaultPath(CaptureRules.inboxFolder)) } catch MarginError.notFound { listed = [] }
        let files = listed
            .filter { $0.components.count == 2 && $0.lastComponent.lowercased().hasSuffix(".md") && !$0.lastComponent.hasPrefix(".") }
        var items: [InboxItem] = []
        for path in files {
            guard let (content, _) = try? await store.read(path) else { continue }
            let stem = String(path.lastComponent.dropLast(3))
            if let item = CaptureRules.parseInboxFile(stem: stem, content: content, fallback: clock.localNow) { items.append(item) }
        }
        return CaptureRules.sortInbox(items)
    }

    /// The file, content, version and parsed item of an inbox item id.
    private func inboxFile(_ id: String) async throws -> (path: VaultPath, item: InboxItem, version: ContentHash) {
        guard !id.isEmpty, !id.contains("/"), !id.hasPrefix("."),
              let path = try? VaultPath(components: [CaptureRules.inboxFolder, id + ".md"]),
              await store.exists(path), let (content, version) = try? await store.read(path),
              let item = CaptureRules.parseInboxFile(stem: id, content: content, fallback: clock.localNow)
        else { throw MarginError.notFound("No inbox item \(id)") }
        return (path, item, version)
    }

    func inboxTriage(item id: String, course courseID: CourseID, when: LocalDate?, kind: InboxKind?, actor: Actor,
                     baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let (path, item, version) = try await inboxFile(id)
        guard let course = model.entry(courseID) else { throw MarginError.notFound("No course \(courseID)") }
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Inbox item \(id)")
        let removed = ChangeSet.Entry(path: path.rawValue, kind: .deleted, beforeHash: version.hex)
        var entries: [ChangeSet.Entry]
        if (kind ?? item.kind) == .task {
            let parts = CaptureRules.taskParts(ofInboxText: item.text, when: when, clock: clock)
            let entry = try await appendTaskLine({ CaptureRules.taskLine(text: parts.text, tags: [], due: parts.due, id: $0) },
                                                 course: course, dryRun: dryRun)
            entries = [entry, removed]
        } else {
            var entry = try await createNote(in: course, text: item.text, tags: [], date: when ?? item.captured.date, dryRun: dryRun)
            entry.kind = .moved; entry.fromPath = path.rawValue; entry.beforeHash = version.hex
            entries = [entry]
        }
        // The new content is on disk before the inbox file goes: a failure here leaves a copy, not a loss.
        if !dryRun { try await store.trash(path) }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func inboxDelete(item id: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                     idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let (path, _, version) = try await inboxFile(id)
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Inbox item \(id)")
        if !dryRun { try await store.trash(path) }
        return finish(actor: actor, entries: [.init(path: path.rawValue, kind: .deleted, beforeHash: version.hex)],
                      dryRun: dryRun, key: idempotencyKey)
    }
}
