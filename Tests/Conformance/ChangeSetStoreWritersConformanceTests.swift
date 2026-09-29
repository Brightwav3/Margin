import Foundation
import Testing
@testable import MarginCore

/// Every write that returns a `ChangeSet` is recorded and can be undone, not only `NoteRepository`'s:
/// capture, inbox triage, task due dates and the course writer. Same suite for the fixture and the
/// vault implementation; state is compared through the services, so both must agree.
@Suite struct ChangeSetStoreWritersConformanceTests {
    /// What a user can see of the world: courses, notes per course, inbox, tasks, timetable.
    struct View: Equatable {
        var courses: [Course]
        var semesters: [Semester]
        var notes: [String]
        var inbox: [String]
        var tasks: [String]
        var week: [SessionOccurrence]
    }

    private func view(_ h: Harness) async throws -> View {
        let notes = try await h.notes.notes(course: nil).map { "\($0.id)@\($0.courseID ?? "-")" }.sorted()
        let inbox = try await h.inbox.items().map(\.id).sorted()
        var tasks: [String] = []
        for c in try await h.courses.courses(query: nil) { tasks += try await h.tasks.tasks(course: c.id).map { "\($0.id):\($0.done)" } }
        return View(courses: try await h.courses.courses(query: nil), semesters: try await h.courses.semesters(),
                    notes: notes, inbox: inbox, tasks: tasks.sorted(), week: (try? await h.courses.sessions(week: 5)) ?? [])
    }

    /// Runs `write`, checks it is recorded, undoes it (the view is the one before), redoes it (the
    /// view is the one after) and undoes the redo again.
    private func roundTrip(_ h: Harness, _ what: String, _ write: () async throws -> ChangeSet) async throws {
        let before = try await view(h)
        let cs = try await write()
        #expect(!cs.entries.isEmpty, "\(what) changed nothing")
        let after = try await view(h)
        #expect(after != before, "\(what) did not change the view")
        let listed = try await h.changes.changes(limit: 1)
        #expect(listed.first?.id == cs.id, "\(what) was not recorded")

        let undo = try await h.changes.undo(id: cs.id, actor: .user)
        #expect(try await view(h) == before, "\(what): undo did not restore the view")
        #expect(undo.revertsID == cs.id)

        let redo = try await h.changes.undo(id: undo.id, actor: .user)
        #expect(try await view(h) == after, "\(what): redo did not bring the change back")
        _ = try await h.changes.undo(id: redo.id, actor: .user)
        #expect(try await view(h) == before, "\(what): second undo did not restore the view")
    }

    // MARK: Capture and inbox

    @Test(arguments: HarnessKind.allCases)
    func undoingACaptureToTheInbox(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            try await roundTrip(h, "capture to inbox") {
                try await h.capture.commit(CaptureDraft(text: "Email the registrar"), actor: testActor, dryRun: false, idempotencyKey: nil)
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingACaptureThatCreatesTheTasksNoteAndOneThatAppends(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            // The first task line creates `Tasks.md` of the course, the second appends to it.
            try await roundTrip(h, "capture creating Tasks.md") {
                try await h.capture.commit(CaptureDraft(text: "Read chapter 7", course: "econ"), actor: testActor, dryRun: false, idempotencyKey: nil)
            }
            _ = try await h.capture.commit(CaptureDraft(text: "Read chapter 7", course: "econ"), actor: .user, dryRun: false, idempotencyKey: nil)
            try await roundTrip(h, "capture appending a task") {
                try await h.capture.commit(CaptureDraft(text: "Read chapter 8", course: "econ"), actor: testActor, dryRun: false, idempotencyKey: nil)
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingACaptureThatCreatesANote(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            try await roundTrip(h, "capture as note") {
                try await h.capture.commit(CaptureDraft(text: "Notes on the lecture", course: "hist", kind: .note),
                                           actor: testActor, dryRun: false, idempotencyKey: nil)
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingAnInboxTriageAsTaskAndAsNote(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let items = try await h.inbox.items()
            let task = try #require(items.first { $0.kind == .task })
            let other = try #require(items.first { $0.id != task.id })
            try await roundTrip(h, "triage as task") {
                try await h.inbox.triage(item: task.id, course: "bio", when: nil, kind: .task, actor: testActor,
                                         baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
            try await roundTrip(h, "triage as note") {
                try await h.inbox.triage(item: other.id, course: "hist", when: nil, kind: .note, actor: testActor,
                                         baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingAnInboxDelete(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let item = try #require(try await h.inbox.items().first)
            try await roundTrip(h, "inbox delete") {
                try await h.inbox.delete(item: item.id, actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
        }
    }

    // MARK: Task due dates

    @Test(arguments: HarnessKind.allCases)
    func undoingADueDateRestoresTheFileByteForByte(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = "math/assignments"
            let before = try await h.rawContent(note)
            let cs = try await h.tasks.setDue(id: "task-math-problem-set-4", due: LocalDate.literal(2026, 10, 3), actor: testActor,
                                              baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(try await h.rawContent(note) != before)
            _ = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(try await h.rawContent(note) == before)
        }
    }

    // MARK: Courses

    @Test(arguments: HarnessKind.allCases)
    func undoingCourseCreateRenameStyleAndOverride(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            try await roundTrip(h, "create course") {
                try await h.writer.create(NewCourse(name: "Statistics", semester: "fall-2026", code: "STA 101"), actor: testActor,
                                          baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
            try await roundTrip(h, "rename course") {
                try await h.writer.rename(id: "bio", to: "Molecular Biology", renameFolder: false, actor: testActor,
                                          baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
            try await roundTrip(h, "restyle course") {
                try await h.writer.setStyle(id: "bio", icon: "science", color: "econ", actor: testActor,
                                            baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
            let tuesday = LocalDate.literal(2026, 9, 29)
            try await roundTrip(h, "cancel a class") {
                try await h.writer.override(session: SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday,
                                                                     cancelled: true, note: "Professor ill"),
                                            actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingARenameThatMovesTheCourseFolder(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            try await roundTrip(h, "rename with folder") {
                try await h.writer.rename(id: "bio", to: "Molecular Biology", renameFolder: true, actor: testActor,
                                          baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
            // The notes of the course are readable again where they were.
            let note = try await h.notes.open(id: "bio/glossary")
            #expect(note.summary.courseID == "bio")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingAnArchiveRestoresTheSemester(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await view(h)
            let cs = try await h.writer.setArchived(semester: "fall-2026", true, actor: testActor, baseVersion: nil,
                                                    dryRun: false, idempotencyKey: nil)
            #expect(try await h.courses.courses(query: nil).isEmpty)
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(try await view(h) == before)
            // Writable again. A note created now goes into the archive with its folder when the archive is
            // redone, and stays readable there: nothing is lost.
            _ = try await h.notes.create(course: "bio", title: "After restore", kind: .note, text: "kept\n", actor: .user,
                                         baseVersion: nil, dryRun: false, idempotencyKey: nil)
            _ = try await h.changes.undo(id: undo.id, actor: .user)
            #expect(try await h.courses.courses(query: nil).isEmpty)
            #expect(try await h.notes.open(id: "bio/after-restore").text == "kept\n")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aFailedWriterCallLeavesNoRecord(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            do {
                _ = try await h.writer.rename(id: "chem", to: "Cell Biology", renameFolder: true, actor: .user, baseVersion: nil,
                                              dryRun: false, idempotencyKey: nil)
                Issue.record("a taken folder name must be refused")
            } catch let e as MarginError { #expect(e.code == "conflict") }
            _ = try await h.capture.commit(CaptureDraft(text: "dry", course: "econ"), actor: .user, dryRun: true, idempotencyKey: nil)
            let listed = try await h.changes.changes(limit: nil)
            #expect(listed.isEmpty)
        }
    }
}
