import Foundation
import Testing
@testable import MarginCore

/// One suite, run against `FixtureCaptureService` and `VaultCaptureService` (contract §5).
/// The fixture clock is Monday 28 Sep 2026, 13:24.
@Suite struct CaptureServiceConformanceTests {
    static let inboxPath = "_inbox/2026-09-28 1324 Email Dr. Okafor about lab partner.md"

    private func taskIDPattern(_ s: String) -> Bool {
        guard let r = s.range(of: "^t-") else { return false }
        let id = s[r.upperBound...]
        return (4...6).contains(id.count) && id.allSatisfy { StableIDGenerator.alphabet.contains($0) }
    }

    // MARK: parse

    @Test(arguments: HarnessKind.allCases)
    func parseFindsCourseDateAndTags(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let draft = try await h.capture.parse("Read chapter 7 for bio @2026-10-02 #midterm")
            #expect(draft.course == "bio")
            #expect(draft.due == LocalDate(year: 2026, month: 10, day: 2))
            #expect(draft.tags == ["midterm"])
            #expect(draft.kind == .task)
            let plain = try await h.capture.parse("Buy printer paper")
            #expect(plain.course == nil)
            #expect(plain.text == "Buy printer paper")
            let empty = try await h.capture.parse("   ")
            #expect(empty.text.isEmpty)
        }
    }

    // MARK: Inbox

    @Test(arguments: HarnessKind.allCases)
    func withoutCourseTheCaptureLandsInTheInbox(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.capture.commit(CaptureDraft(text: "Email Dr. Okafor about lab partner"), actor: testActor,
                                                dryRun: false, idempotencyKey: nil)
            #expect(cs.actor == testActor)
            #expect(!cs.isDryRun)
            #expect(cs.entries.count == 1)
            let e = try #require(cs.entries.first)
            #expect(e.kind == .created)
            #expect(e.path == Self.inboxPath)
            #expect(e.beforeHash == nil)
            if let text = h.readFile(e.path) {
                #expect(text == """
                    ---
                    captured: 2026-09-28T13:24
                    source: quick-capture
                    kind: task
                    ---
                    Email Dr. Okafor about lab partner

                    """)
                #expect(e.afterHash == ContentHash(of: text).hex)
            } else if h.kind == .vault {
                Issue.record("the inbox file is missing")
            }
            // It is not a note and not a task of any course.
            let all = try await h.notes.notes(course: nil)
            #expect(all.count == 19)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aTaskWithDueDateWithoutCourseKeepsThemInTheText(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let draft = CaptureDraft(text: "Buy a lab coat", due: LocalDate(year: 2026, month: 10, day: 2), tags: ["lab"])
            let cs = try await h.capture.commit(draft, actor: .user, dryRun: false, idempotencyKey: nil)
            let path = try #require(cs.entries.first?.path)
            #expect(path == "_inbox/2026-09-28 1324 Buy a lab coat.md")
            if let text = h.readFile(path) { #expect(text.hasSuffix("---\nBuy a lab coat #lab @2026-10-02\n")) }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func twoCapturesInTheSameMinuteGetDifferentFiles(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let a = try await h.capture.commit(CaptureDraft(text: "Same words"), actor: .user, dryRun: false, idempotencyKey: nil)
            let b = try await h.capture.commit(CaptureDraft(text: "Same words"), actor: .user, dryRun: false, idempotencyKey: nil)
            #expect(a.entries.first?.path == "_inbox/2026-09-28 1324 Same words.md")
            #expect(b.entries.first?.path == "_inbox/2026-09-28 1324 Same words 2.md")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func kindOfADraftIsWrittenToTheInboxFile(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.capture.commit(CaptureDraft(text: "Khan Academy", kind: .link), actor: .user, dryRun: false,
                                                idempotencyKey: nil)
            let path = try #require(cs.entries.first?.path)
            if let text = h.readFile(path) { #expect(text.contains("kind: link\n")) }
        }
    }

    // MARK: Tasks of a course

    @Test(arguments: HarnessKind.allCases)
    func aTaskOfACourseIsAppendedToItsTasksNote(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.tasks.tasks(course: "econ")
            let draft = CaptureDraft(text: "Read chapter 7", course: "econ", due: LocalDate(year: 2026, month: 10, day: 2), tags: ["reading"])
            let first = try await h.capture.commit(draft, actor: testActor, dryRun: false, idempotencyKey: nil)
            let e1 = try #require(first.entries.first)
            #expect(first.entries.count == 1)
            #expect(e1.kind == .created)                      // the note did not exist
            #expect(e1.path == "Fall 2026/Macroeconomics/Tasks.md")
            let noteID = try #require(e1.noteID)

            let second = try await h.capture.commit(CaptureDraft(text: "Email the tutor", course: "econ"), actor: testActor,
                                                    dryRun: false, idempotencyKey: nil)
            let e2 = try #require(second.entries.first)
            #expect(e2.kind == .modified)
            #expect(e2.path == e1.path)
            #expect(e2.noteID == noteID)
            #expect(e2.beforeHash == e1.afterHash)

            let after = try await h.tasks.tasks(course: "econ")
            #expect(after.count == before.count + 2)
            let added = after.filter { t in !before.contains { $0.id == t.id } }
            let chapter = try #require(added.first { $0.text.hasPrefix("Read chapter 7") })
            #expect(chapter.due == LocalDate(year: 2026, month: 10, day: 2))
            #expect(!chapter.done)
            #expect(chapter.source.courseID == "econ")
            #expect(chapter.source.noteID == noteID)
            let tutor = try #require(added.first { $0.text == "Email the tutor" })
            #expect(tutor.due == nil)
            #expect(tutor.id != chapter.id)
            #expect(!TaskIDShape.isPlaceholder(chapter.id) && !TaskIDShape.isPlaceholder(tutor.id))

            let note = try await h.notes.open(id: noteID)
            #expect(note.summary.title == "Tasks")
            #expect(note.text.hasPrefix("# Tasks\n"))
            #expect(note.text.hasSuffix("\n"))
            let lines = note.text.split(separator: "\n").map(String.init)
            #expect(lines.contains { $0.hasPrefix("- [ ] Read chapter 7 #reading @2026-10-02 ^t-") && taskIDPattern($0) })
            #expect(lines.contains { $0.hasPrefix("- [ ] Email the tutor ^t-") && taskIDPattern($0) })
            #expect(e2.afterHash == note.version || h.kind == .fixture)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aTaskIsAppendedToAnExistingTasksNote(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.capture.commit(CaptureDraft(text: "one", course: "chem"), actor: .user, dryRun: false, idempotencyKey: nil)
            let notesBefore = try await h.notes.notes(course: "chem")
            _ = try await h.capture.commit(CaptureDraft(text: "two", course: "chem"), actor: .user, dryRun: false, idempotencyKey: nil)
            let notesAfter = try await h.notes.notes(course: "chem")
            #expect(notesAfter.map(\.id) == notesBefore.map(\.id))   // no second Tasks note
            let tasksNote = try #require(notesAfter.first { $0.title == "Tasks" })
            #expect(tasksNote.totalTasks == 2)
            #expect(tasksNote.openTasks == 2)
        }
    }

    // MARK: Notes of a course

    @Test(arguments: HarnessKind.allCases)
    func aNoteCaptureCreatesANoteInTheCourse(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let draft = CaptureDraft(text: "Compare 1848 to the Arab Spring\nboth started with a spark", course: "hist", tags: ["essay"], kind: .note)
            let cs = try await h.capture.commit(draft, actor: .user, dryRun: false, idempotencyKey: nil)
            let e = try #require(cs.entries.first)
            #expect(e.kind == .created)
            #expect(e.path.hasSuffix("/Compare 1848 to the Arab Spring.md"))
            let note = try await h.notes.open(id: try #require(e.noteID))
            #expect(note.summary.courseID == "hist")
            #expect(note.summary.title == "Compare 1848 to the Arab Spring")
            #expect(note.summary.kind == .note)
            #expect(note.summary.date == LocalDate(year: 2026, month: 9, day: 28))
            #expect(note.text == "# Compare 1848 to the Arab Spring\n\nCompare 1848 to the Arab Spring\nboth started with a spark\n")
            if let file = h.readFile(e.path) {
                #expect(file.contains("class: \"[[Modern Europe]]\"\n"))
                #expect(file.contains("tags:\n  - essay\n"))
                #expect(file.contains("type: note\n"))
            }
            // The same title again does not collide.
            let again = try await h.capture.commit(draft, actor: .user, dryRun: false, idempotencyKey: nil)
            #expect(again.entries.first?.path.hasSuffix("/Compare 1848 to the Arab Spring 2.md") == true)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aShortNoteHasOnlyItsHeading(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.capture.commit(CaptureDraft(text: "Osmosis is not diffusion", course: "bio", kind: .note),
                                                actor: .user, dryRun: false, idempotencyKey: nil)
            let note = try await h.notes.open(id: try #require(cs.entries.first?.noteID))
            #expect(note.text == "# Osmosis is not diffusion\n")
        }
    }

    // MARK: attachTo

    @Test(arguments: HarnessKind.allCases)
    func aCaptureCanBeAttachedToANote(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: "bio/lecture-8")
            let task = try await h.capture.commit(
                CaptureDraft(text: "Ask about the osmosis question", due: LocalDate(year: 2026, month: 9, day: 29), attachTo: "bio/lecture-8"),
                actor: testActor, dryRun: false, idempotencyKey: nil)
            #expect(task.entries.count == 1)
            #expect(task.entries.first?.kind == .modified)
            #expect(task.entries.first?.noteID == "bio/lecture-8")
            #expect(task.entries.first?.beforeHash == before.version)
            let mid = try await h.notes.open(id: "bio/lecture-8")
            #expect(mid.text.hasPrefix(before.text))
            #expect(mid.text.split(separator: "\n").last.map { $0.hasPrefix("- [ ] Ask about the osmosis question @2026-09-29 ^t-") } == true)
            #expect(task.entries.first?.afterHash == mid.version)

            let paragraph = try await h.capture.commit(
                CaptureDraft(text: "Remember the sodium gradient", kind: .note, attachTo: "bio/lecture-8"),
                actor: testActor, dryRun: false, idempotencyKey: nil)
            #expect(paragraph.entries.first?.kind == .modified)
            let after = try await h.notes.open(id: "bio/lecture-8")
            #expect(after.text.hasSuffix("\n\nRemember the sodium gradient\n"))
            #expect(after.summary.openTasks == before.summary.openTasks + 1)
        }
    }

    // MARK: Write context

    @Test(arguments: HarnessKind.allCases)
    func aDryRunChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let drafts = [
                CaptureDraft(text: "dry inbox"),
                CaptureDraft(text: "dry task", course: "bio"),
                CaptureDraft(text: "dry note", course: "bio", kind: .note),
                CaptureDraft(text: "dry attach", attachTo: "bio/glossary"),
            ]
            let notesBefore = try await h.notes.notes(course: nil)
            let tasksBefore = try await h.tasks.tasks(course: "bio")
            let glossary = try await h.notes.open(id: "bio/glossary")
            for draft in drafts {
                let dry = try await h.capture.commit(draft, actor: .user, dryRun: true, idempotencyKey: "k-\(draft.text)")
                #expect(dry.isDryRun)
                #expect(dry.entries.count == 1)
                for e in dry.entries { #expect(h.readFile(e.path) == nil || e.kind == .modified) }
            }
            #expect(try await h.notes.notes(course: nil).map(\.id) == notesBefore.map(\.id))
            #expect(try await h.tasks.tasks(course: "bio").count == tasksBefore.count)
            #expect(try await h.notes.open(id: "bio/glossary").version == glossary.version)
            // A dry run does not use up the idempotency key.
            let real = try await h.capture.commit(drafts[0], actor: .user, dryRun: false, idempotencyKey: "k-dry inbox")
            #expect(!real.isDryRun)
            let dry = try await h.capture.commit(drafts[0], actor: .user, dryRun: true, idempotencyKey: nil)
            #expect(real.entries.first?.path == "_inbox/2026-09-28 1324 dry inbox.md")
            #expect(dry.entries.first?.path == "_inbox/2026-09-28 1324 dry inbox 2.md")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func theSameIdempotencyKeyWritesOnce(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let draft = CaptureDraft(text: "Once only", course: "math")
            let first = try await h.capture.commit(draft, actor: testActor, dryRun: false, idempotencyKey: "key-1")
            let before = try await h.tasks.tasks(course: "math")
            let second = try await h.capture.commit(draft, actor: testActor, dryRun: false, idempotencyKey: "key-1")
            #expect(second == first)
            #expect(second.idempotencyKey == "key-1")
            #expect(try await h.tasks.tasks(course: "math").count == before.count)
            // Another actor with the same key is another request.
            let other = try await h.capture.commit(draft, actor: .user, dryRun: false, idempotencyKey: "key-1")
            #expect(other.id != first.id)
            #expect(try await h.tasks.tasks(course: "math").count == before.count + 1)
        }
    }

    // MARK: Errors

    @Test(arguments: HarnessKind.allCases)
    func badDraftsAreRefusedAndWriteNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let notesBefore = try await h.notes.notes(course: nil).count
            let cases: [(CaptureDraft, String)] = [
                (CaptureDraft(text: ""), "invalid"),
                (CaptureDraft(text: " \n\t "), "invalid"),
                (CaptureDraft(text: "x", course: "nope"), "notFound"),
                (CaptureDraft(text: "x", course: "nope", kind: .note), "notFound"),
                (CaptureDraft(text: "x", attachTo: "nope/nothing"), "notFound"),
            ]
            for (draft, code) in cases {
                for dryRun in [false, true] {
                    do { _ = try await h.capture.commit(draft, actor: .user, dryRun: dryRun, idempotencyKey: nil); Issue.record("\(draft) should throw") }
                    catch let e as MarginError { #expect(e.code == code, "\(draft): \(e)") }
                }
            }
            #expect(try await h.notes.notes(course: nil).count == notesBefore)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aCaptureIsSeenByTheTaskServiceUpdates(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let stream = h.tasks.updates
            _ = try await h.capture.commit(CaptureDraft(text: "Watch me", course: "bio"), actor: .user, dryRun: false, idempotencyKey: nil)
            let update = await next(from: stream, timeout: 10) { $0.courseIDs.contains("bio") }
            #expect(update != nil)
        }
    }
}

private enum TaskIDShape {
    static func isPlaceholder(_ id: String) -> Bool { StableIDGenerator.isPlaceholderTaskID(id) }
}
