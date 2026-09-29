import Foundation

/// `InboxService` on the fixture world. Same rules as `VaultBackend` (see `InboxService`).
extension FixtureStore {
    func inboxItems() -> [InboxItem] { CaptureRules.sortInbox(inbox) }

    private func inboxItem(_ id: String) throws -> InboxItem {
        guard let item = inbox.first(where: { $0.id == id }) else { throw MarginError.notFound("No inbox item \(id)") }
        return item
    }

    private func inboxPath(_ item: InboxItem) -> String {
        "\(CaptureRules.inboxFolder)/\(inboxStems[item.id] ?? item.id).md"
    }

    private func inboxVersion(_ item: InboxItem) -> String { Self.version(of: CaptureRules.inboxFile(item)) }

    func inboxTriage(item id: String, course courseID: CourseID, when: LocalDate?, kind: InboxKind?, actor: Actor,
                     baseVersion: String?, dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let item = try inboxItem(id)
        let course = try self.course(id: courseID)
        try requireBaseVersion(baseVersion, matches: inboxVersion(item), what: "Inbox item \(id)")
        let removed = ChangeSet.Entry(path: inboxPath(item), kind: .deleted, beforeHash: inboxVersion(item))
        var entries: [ChangeSet.Entry]
        var changed: StoredNote
        if (kind ?? item.kind) == .task {
            let parts = CaptureRules.taskParts(ofInboxText: item.text, when: when, clock: clock)
            let (note, entry) = try appendToTasksNote(course: course, text: parts.text, tags: [], due: parts.due)
            (changed, entries) = (note, [entry, removed])
        } else {
            let (note, entry) = newCourseNote(course: course, text: item.text, date: when ?? item.captured.date)
            var moved = entry
            moved.kind = .moved; moved.fromPath = removed.path; moved.beforeHash = removed.beforeHash
            (changed, entries) = (note, [moved])
        }
        if !dryRun {
            notes[changed.summary.id] = changed
            inbox.removeAll { $0.id == id }
            inboxStems[id] = nil
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func inboxDelete(item id: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                     idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let item = try inboxItem(id)
        try requireBaseVersion(baseVersion, matches: inboxVersion(item), what: "Inbox item \(id)")
        let entry = ChangeSet.Entry(path: inboxPath(item), kind: .deleted, beforeHash: inboxVersion(item))
        if !dryRun {
            inbox.removeAll { $0.id == id }
            inboxStems[id] = nil
        }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }
}
