import Foundation
import Testing
@testable import MarginCore

/// One suite, run against `FixtureInboxService` and `VaultInboxService` (contract §5). The vault
/// is the sample vault of `Fixtures.week5`, whose five inbox files are the fixture's inbox items.
/// The fixture clock is Monday 28 Sep 2026, 13:24.
@Suite struct InboxServiceConformanceTests {
    static let texts = [
        "Email Dr. Okafor about lab partner",
        "Idea: compare 1848 to Arab Spring for essay",
        "Khan Academy — eigenvectors intro",
        "Whiteboard photo, ECON tutorial",
        "Print lab safety form",
    ]

    /// The item with `text` (fixture and vault ids differ, the texts do not).
    private func item(_ h: Harness, _ text: String) async throws -> InboxItem {
        try #require(try await h.inbox.items().first { $0.text == text }, "no inbox item \(text)")
    }

    private func trashed(_ h: Harness, suffix: String) -> Bool {
        h.listFiles(".margin/trash").contains { $0.hasSuffix(suffix) }
    }

    // MARK: items

    @Test(arguments: HarnessKind.allCases)
    func itemsAreTheFiveFixtureItemsNewestFirst(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let items = try await h.inbox.items()
            #expect(items.map(\.text) == Self.texts)
            #expect(items.map(\.kind) == [.task, .note, .link, .image, .task])
            #expect(items.map(\.source) == [.phone, .quickCapture, .share, .phone, .quickCapture])
            #expect(items.map(\.captured) == Fixtures.week5.inbox.map(\.captured))
            #expect(items.map(\.captured) == items.map(\.captured).sorted(by: >))
            #expect(Set(items.map(\.id)).count == 5)
            #expect(items.allSatisfy { !$0.text.isEmpty })
            if h.kind == .vault {
                #expect(items[0].id == "2026-09-28 0912 Email Dr. Okafor about lab partner")
                #expect(h.readFile("_inbox/\(items[0].id).md") != nil)
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aNewCaptureIsTheFirstItem(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.capture.commit(CaptureDraft(text: "Fresh thought", kind: .note), actor: .user, dryRun: false, idempotencyKey: nil)
            let items = try await h.inbox.items()
            #expect(items.count == 6)
            let first = try #require(items.first)
            #expect(first.text == "Fresh thought")
            #expect(first.kind == .note)
            #expect(first.source == .quickCapture)
            #expect(first.captured == h.clock.localNow)
            #expect(cs.entries.first?.path == "_inbox/\(first.id).md")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aFileWithoutFrontmatterIsAnItemToo(kind: HarnessKind) async throws {
        guard kind == .vault else { return }
        try await withHarness(kind) { h in
            // Another program drops a bare markdown file into the inbox.
            try h.writeFile("_inbox/2026-09-27 2210 Call the bursar.md", "Call the bursar\n")
            try h.writeFile("_inbox/empty.md", "  \n")
            let items = try await h.inbox.items()
            let bare = try #require(items.first { $0.text == "Call the bursar" })
            #expect(bare.kind == .note)
            #expect(bare.source == .share)
            #expect(bare.captured == LocalDateTime(iso: "2026-09-27T22:10"))
            #expect(!items.contains { $0.id == "empty" })
        }
    }

    // MARK: triage as task

    @Test(arguments: HarnessKind.allCases)
    func triagingATaskAppendsItToTheCourseAndRemovesTheInboxFile(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let it = try await item(h, Self.texts[0])
            let before = try await h.tasks.tasks(course: "bio")
            let cs = try await h.inbox.triage(item: it.id, course: "bio", when: nil, kind: nil, actor: testActor, baseVersion: nil,
                                              dryRun: false, idempotencyKey: nil)
            #expect(cs.actor == testActor)
            #expect(cs.entries.count == 2)
            let tasksEntry = cs.entries[0]
            #expect(tasksEntry.kind == .created)
            #expect(tasksEntry.path == "Fall 2026/Cell Biology/Tasks.md")
            let removed = cs.entries[1]
            #expect(removed.kind == .deleted)
            #expect(removed.path == "_inbox/2026-09-28 0912 Email Dr. Okafor about lab partner.md")
            #expect(removed.beforeHash == ContentHash(of: SampleVaultGenerator.inboxFile(Fixtures.week5.inbox[0])).hex)

            let items = try await h.inbox.items()
            #expect(items.count == 4)
            #expect(!items.contains { $0.text == Self.texts[0] })
            let after = try await h.tasks.tasks(course: "bio")
            #expect(after.count == before.count + 1)
            let added = try #require(after.first { $0.text == Self.texts[0] })
            #expect(added.due == nil)
            #expect(!added.done)
            #expect(!StableIDGenerator.isPlaceholderTaskID(added.id))
            if h.kind == .vault {
                #expect(h.readFile(removed.path) == nil)
                #expect(trashed(h, suffix: "-2026-09-28 0912 Email Dr. Okafor about lab partner.md"))
                let tasksFile = try #require(h.readFile(tasksEntry.path))
                #expect(tasksFile.contains("\n- [ ] Email Dr. Okafor about lab partner ^t-"))
                #expect(tasksFile.contains("class: \"[[Cell Biology]]\""))
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func whenSetsTheDueDate(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let it = try await item(h, Self.texts[4])
            _ = try await h.inbox.triage(item: it.id, course: "chem", when: LocalDate(year: 2026, month: 10, day: 5), kind: .task,
                                         actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let task = try #require(try await h.tasks.tasks(course: "chem").first { $0.text == Self.texts[4] })
            #expect(task.due == LocalDate(year: 2026, month: 10, day: 5))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aDueDateInTheTextIsRestoredAndWhenOverridesIt(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let draft = CaptureDraft(text: "Hand in the form", due: LocalDate(year: 2026, month: 10, day: 2), tags: ["admin"])
            _ = try await h.capture.commit(draft, actor: .user, dryRun: false, idempotencyKey: nil)
            _ = try await h.capture.commit(CaptureDraft(text: "Hand in the poster", due: LocalDate(year: 2026, month: 10, day: 2)),
                                           actor: .user, dryRun: false, idempotencyKey: nil)
            let form = try await item(h, "Hand in the form #admin @2026-10-02")
            let poster = try await item(h, "Hand in the poster @2026-10-02")
            _ = try await h.inbox.triage(item: form.id, course: "hist", when: nil, kind: nil, actor: .user, baseVersion: nil,
                                         dryRun: false, idempotencyKey: nil)
            _ = try await h.inbox.triage(item: poster.id, course: "hist", when: LocalDate(year: 2026, month: 10, day: 9), kind: nil,
                                         actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let tasks = try await h.tasks.tasks(course: "hist")
            let a = try #require(tasks.first { $0.text.hasPrefix("Hand in the form") })
            #expect(a.due == LocalDate(year: 2026, month: 10, day: 2))
            #expect(a.text == "Hand in the form #admin")
            let b = try #require(tasks.first { $0.text == "Hand in the poster" })
            #expect(b.due == LocalDate(year: 2026, month: 10, day: 9))
        }
    }

    // MARK: triage as note

    @Test(arguments: HarnessKind.allCases)
    func triagingANoteMovesItIntoTheCourseFolder(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let it = try await item(h, Self.texts[1])
            let cs = try await h.inbox.triage(item: it.id, course: "hist", when: nil, kind: nil, actor: testActor, baseVersion: nil,
                                              dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1)
            let e = try #require(cs.entries.first)
            #expect(e.kind == .moved)
            #expect(e.fromPath == "_inbox/2026-09-28 0840 Idea- compare 1848 to Arab Spring for essay.md")
            #expect(e.path == "Fall 2026/Modern Europe/Idea- compare 1848 to Arab Spring for essay.md")
            #expect(e.beforeHash != nil && e.afterHash != nil)
            let note = try await h.notes.open(id: try #require(e.noteID))
            #expect(note.summary.courseID == "hist")
            #expect(note.summary.title == "Idea: compare 1848 to Arab Spring for essay")
            #expect(note.summary.date == Fixtures.week5.inbox[1].captured.date)
            #expect(note.text == "# Idea: compare 1848 to Arab Spring for essay\n")
            #expect(try await h.inbox.items().count == 4)
            if h.kind == .vault {
                #expect(h.readFile(e.fromPath ?? "") == nil)
                #expect(h.readFile(e.path) != nil)
                #expect(e.afterHash == ContentHash(of: h.readFile(e.path) ?? "").hex)
                #expect(trashed(h, suffix: "-2026-09-28 0840 Idea- compare 1848 to Arab Spring for essay.md"))
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func linksAndImagesBecomeNotesAndKindCanBeOverridden(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let link = try await item(h, Self.texts[2])
            let cs = try await h.inbox.triage(item: link.id, course: "math", when: LocalDate(year: 2026, month: 9, day: 30), kind: nil,
                                              actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.first?.kind == .moved)
            let note = try await h.notes.open(id: try #require(cs.entries.first?.noteID))
            #expect(note.summary.date == LocalDate(year: 2026, month: 9, day: 30))
            #expect(note.summary.title == Self.texts[2])

            // A note item triaged as a task, a task item triaged as a note.
            let idea = try await item(h, Self.texts[1])
            let asTask = try await h.inbox.triage(item: idea.id, course: "hist", when: nil, kind: .task, actor: .user, baseVersion: nil,
                                                  dryRun: false, idempotencyKey: nil)
            #expect(asTask.entries.map(\.kind) == [.created, .deleted])
            let mail = try await item(h, Self.texts[0])
            let asNote = try await h.inbox.triage(item: mail.id, course: "bio", when: nil, kind: .note, actor: .user, baseVersion: nil,
                                                  dryRun: false, idempotencyKey: nil)
            #expect(asNote.entries.map(\.kind) == [.moved])
            #expect(try await h.inbox.items().count == 2)
        }
    }

    // MARK: delete

    @Test(arguments: HarnessKind.allCases)
    func deleteMovesTheItemToTheTrash(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let it = try await item(h, Self.texts[3])
            let cs = try await h.inbox.delete(item: it.id, actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1)
            let e = try #require(cs.entries.first)
            #expect(e.kind == .deleted)
            #expect(e.path == "_inbox/2026-09-27 1705 Whiteboard photo, ECON tutorial.md")
            #expect(e.afterHash == nil)
            #expect(try await h.inbox.items().map(\.text) == [Self.texts[0], Self.texts[1], Self.texts[2], Self.texts[4]])
            if h.kind == .vault {
                #expect(h.readFile(e.path) == nil)
                #expect(trashed(h, suffix: "-2026-09-27 1705 Whiteboard photo, ECON tutorial.md"))
            }
            do { _ = try await h.inbox.delete(item: it.id, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
                 Issue.record("a second delete should throw") }
            catch let e as MarginError { #expect(e.code == "notFound") }
        }
    }

    // MARK: Write context

    @Test(arguments: HarnessKind.allCases)
    func aDryRunChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let it = try await item(h, Self.texts[0])
            let notes = try await h.notes.notes(course: nil).count
            let tasks = try await h.tasks.tasks(course: "bio").count
            let triage = try await h.inbox.triage(item: it.id, course: "bio", when: nil, kind: nil, actor: .user, baseVersion: nil,
                                                  dryRun: true, idempotencyKey: "k")
            #expect(triage.isDryRun)
            #expect(triage.entries.map(\.kind) == [.created, .deleted])
            let asNote = try await h.inbox.triage(item: it.id, course: "bio", when: nil, kind: .note, actor: .user, baseVersion: nil,
                                                  dryRun: true, idempotencyKey: nil)
            #expect(asNote.entries.map(\.kind) == [.moved])
            let delete = try await h.inbox.delete(item: it.id, actor: .user, baseVersion: nil, dryRun: true, idempotencyKey: nil)
            #expect(delete.entries.map(\.kind) == [.deleted])
            #expect(try await h.inbox.items().count == 5)
            #expect(try await h.notes.notes(course: nil).count == notes)
            #expect(try await h.tasks.tasks(course: "bio").count == tasks)
            if h.kind == .vault { #expect(h.readFile(triage.entries[1].path) != nil) }
            // The real call after a dry run with the same key still writes.
            let real = try await h.inbox.triage(item: it.id, course: "bio", when: nil, kind: nil, actor: .user, baseVersion: nil,
                                                dryRun: false, idempotencyKey: "k")
            #expect(!real.isDryRun)
            #expect(try await h.inbox.items().count == 4)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func theSameIdempotencyKeyTriagesOnce(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let it = try await item(h, Self.texts[0])
            let first = try await h.inbox.triage(item: it.id, course: "bio", when: nil, kind: nil, actor: testActor, baseVersion: nil,
                                                 dryRun: false, idempotencyKey: "key-7")
            let tasks = try await h.tasks.tasks(course: "bio").count
            let second = try await h.inbox.triage(item: it.id, course: "bio", when: nil, kind: nil, actor: testActor, baseVersion: nil,
                                                  dryRun: false, idempotencyKey: "key-7")
            #expect(second == first)
            #expect(try await h.tasks.tasks(course: "bio").count == tasks)
            let del = try await h.inbox.delete(item: (try await item(h, Self.texts[4])).id, actor: testActor, baseVersion: nil,
                                               dryRun: false, idempotencyKey: "key-8")
            let again = try await h.inbox.delete(item: "gone", actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: "key-8")
            #expect(again == del)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aStaleBaseVersionIsAConflict(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let it = try await item(h, Self.texts[0])
            let hash = ContentHash(of: SampleVaultGenerator.inboxFile(Fixtures.week5.inbox[0])).hex
            for stale in ["0000", "deadbeef"] {
                do { _ = try await h.inbox.triage(item: it.id, course: "bio", when: nil, kind: nil, actor: .user, baseVersion: stale,
                                                  dryRun: false, idempotencyKey: nil)
                     Issue.record("triage with a stale version should throw") }
                catch let e as MarginError { #expect(e.code == "conflict") }
                do { _ = try await h.inbox.delete(item: it.id, actor: .user, baseVersion: stale, dryRun: false, idempotencyKey: nil)
                     Issue.record("delete with a stale version should throw") }
                catch let e as MarginError { #expect(e.code == "conflict") }
            }
            #expect(try await h.inbox.items().count == 5)
            // The version the file has is accepted.
            _ = try await h.inbox.delete(item: it.id, actor: .user, baseVersion: hash, dryRun: false, idempotencyKey: nil)
            #expect(try await h.inbox.items().count == 4)
        }
    }

    // MARK: Errors

    @Test(arguments: HarnessKind.allCases)
    func unknownItemsAndCoursesAreNotFound(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let it = try await item(h, Self.texts[0])
            let cases: [@Sendable () async throws -> ChangeSet] = [
                { try await h.inbox.triage(item: "nope", course: "bio", when: nil, kind: nil, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) },
                { try await h.inbox.triage(item: it.id, course: "nope", when: nil, kind: nil, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) },
                { try await h.inbox.triage(item: "../bio/lecture", course: "bio", when: nil, kind: nil, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) },
                { try await h.inbox.triage(item: "", course: "bio", when: nil, kind: nil, actor: .user, baseVersion: nil, dryRun: true, idempotencyKey: nil) },
                { try await h.inbox.delete(item: "nope", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) },
            ]
            for run in cases {
                do { _ = try await run(); Issue.record("should throw") }
                catch let e as MarginError { #expect(e.code == "notFound", "\(e)") }
            }
            #expect(try await h.inbox.items().count == 5)
            #expect(try await h.notes.notes(course: nil).count == 19)
        }
    }
}
