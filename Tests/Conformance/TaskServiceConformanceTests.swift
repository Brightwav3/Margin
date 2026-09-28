import Foundation
import Testing
@testable import MarginCore

/// One suite, run against `FixtureTaskService` and `VaultTaskService` (contract §5).
@Suite struct TaskServiceConformanceTests {
    let world = Fixtures.week5

    private func clock(_ y: Int, _ m: Int, _ d: Int, _ hour: Int, _ minute: Int) -> FixedClock {
        FixedClock(local: LocalDateTime(date: .literal(y, m, d), time: .literal(hour, minute)))
    }

    @Test(arguments: HarnessKind.allCases)
    func todayOnMondayIsProblemSet4(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let today = try await h.tasks.today()
            #expect(today.map(\.id) == ["task-math-problem-set-4"])
            #expect(today.first?.label == .today)
            #expect(today.first?.text == "Problem set 4")
            #expect(today.first?.source.courseID == "math")
            #expect(today.first?.source.noteID == "math/assignments")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func upcomingListsOpenTasksAndExamsByDueDate(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let upcoming = try await h.tasks.upcoming()
            #expect(upcoming.map(\.id) == [
                "task-chem-lab-report-tlc",            // Tue 29 Sep
                "exam-bio-2026-10-01-midterm",         // Thu 1 Oct
                "task-hist-essay-proposal",            // Fri 2 Oct, hist before phil
                "task-phil-response-paper",
                "exam-econ-2026-10-06-quiz-3",         // Tue 6 Oct
                "exam-math-2026-10-14-midterm",        // Wed 14 Oct
            ])
            #expect(upcoming.map(\.kind) == [.task, .exam, .task, .task, .exam, .exam])
            #expect(upcoming.map(\.label) == [
                .tomorrow, .weekday(.thursday), .weekday(.friday), .weekday(.friday), .date(.literal(2026, 10, 6)), .date(.literal(2026, 10, 14)),
            ])
            let exam = try #require(upcoming.first { $0.kind == .exam })
            #expect(exam.text == "Midterm" && exam.due == .literal(2026, 10, 1) && exam.done == false)
            #expect(exam.source.courseID == "bio" && exam.source.noteID == "bio/_course")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func doneTasksAreOnlyInTheCourseList(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let today = try await h.tasks.today()
            let upcoming = try await h.tasks.upcoming()
            #expect(!(today + upcoming).contains { $0.id == "task-bio-read-chapter-6" })
            let bio = try await h.tasks.tasks(course: "bio")
            let read = try #require(bio.first { $0.id == "task-bio-read-chapter-6" })
            #expect(read.done && read.due == .literal(2026, 9, 30))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func courseTasksFollowTheNotesInOrder(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let bio = try await h.tasks.tasks(course: "bio")
            var expected: [(String, String, Bool, LocalDate?)] = []
            for note in ["bio/assignments", "bio/lecture-7", "bio/lecture-8"] {   // sorted by note id
                for t in world.taskLines(ofNote: note) { expected.append((note, t.text, t.done, t.due)) }
            }
            #expect(bio.count == expected.count && bio.count == 4)
            for (item, exp) in zip(bio, expected) {
                #expect(item.source.noteID == exp.0)
                #expect(item.text == exp.1)
                #expect(item.done == exp.2)
                #expect(item.due == exp.3)
                #expect(item.source.courseID == "bio")
            }
            #expect(!bio.contains { $0.kind == .exam })
            // Lines increase within a note.
            #expect(Set(bio.map(\.id)).count == bio.count)
            let econ = try await h.tasks.tasks(course: "econ")
            #expect(econ.isEmpty)                      // a course without tasks is not an error
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func unknownCourseIsNotFound(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            do { _ = try await h.tasks.tasks(course: "nope"); Issue.record("should throw") }
            catch let e as MarginError { #expect(e.code == "notFound") }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func theDayChangesAtLocalMidnight(kind: HarnessKind) async throws {
        // 23:59 on Monday: still Monday.
        try await withHarness(kind, clock: clock(2026, 9, 28, 23, 59)) { h in
            let today = try await h.tasks.today()
            #expect(today.map(\.id) == ["task-math-problem-set-4"])
            #expect(today.first?.label == .today)
            let upcoming = try await h.tasks.upcoming()
            #expect(upcoming.first?.id == "task-chem-lab-report-tlc" && upcoming.first?.label == .tomorrow)
        }
        // 00:00 on Tuesday: Problem set 4 is overdue, the lab report is due today.
        try await withHarness(kind, clock: clock(2026, 9, 29, 0, 0)) { h in
            let today = try await h.tasks.today()
            #expect(today.map(\.id) == ["task-math-problem-set-4", "task-chem-lab-report-tlc"])
            #expect(today.map(\.label) == [.overdue(days: 1), .today])
            let upcoming = try await h.tasks.upcoming()
            #expect(upcoming.map(\.id).first == "exam-bio-2026-10-01-midterm")
            #expect(!upcoming.contains { $0.id == "task-chem-lab-report-tlc" })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func anExamShowsUpOnItsDayAndNotAfter(kind: HarnessKind) async throws {
        try await withHarness(kind, clock: clock(2026, 10, 1, 9, 0)) { h in
            let today = try await h.tasks.today()
            #expect(today.map(\.id) == ["task-math-problem-set-4", "task-chem-lab-report-tlc", "exam-bio-2026-10-01-midterm"])
            #expect(today.last?.label == .today)
            let upcoming = try await h.tasks.upcoming()
            #expect(!upcoming.contains { $0.id == "exam-bio-2026-10-01-midterm" })
        }
        try await withHarness(kind, clock: clock(2026, 10, 2, 9, 0)) { h in
            let all = try await h.tasks.today() + h.tasks.upcoming()
            #expect(!all.contains { $0.id == "exam-bio-2026-10-01-midterm" })   // over, and not overdue work
            #expect(all.contains { $0.id == "task-hist-essay-proposal" })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func tasksFollowNoteWrites(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = try await h.notes.open(id: "bio/glossary")
            let text = note.text + "\n- [ ] Learn the terms @2026-09-30 ^t-learn\n- [x] Skim the list ^t-skim\n"
            _ = try await h.notes.save(id: "bio/glossary", text: text, actor: .user, baseVersion: note.version,
                                       dryRun: false, idempotencyKey: nil)
            let bio = try await h.tasks.tasks(course: "bio")
            #expect(bio.contains { $0.id == "t-learn" && !$0.done && $0.due == .literal(2026, 9, 30) })
            #expect(bio.contains { $0.id == "t-skim" && $0.done })
            let upcoming = try await h.tasks.upcoming().map(\.id)
            #expect(upcoming.contains("t-learn") && !upcoming.contains("t-skim"))
            // A dry run does not.
            let more = note.text + "\n- [ ] Never saved ^t-never\n"
            _ = try await h.notes.save(id: "bio/glossary", text: more, actor: .user, baseVersion: nil, dryRun: true,
                                       idempotencyKey: nil)
            let after = try await h.tasks.tasks(course: "bio")
            #expect(!after.contains { $0.id == "t-never" })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aMovedNoteTakesItsTasksToTheNewCourse(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.notes.move(id: "bio/lecture-8", toCourse: "chem", actor: .user, baseVersion: nil,
                                       dryRun: false, idempotencyKey: nil)
            let bio = try await h.tasks.tasks(course: "bio").map(\.source.noteID)
            #expect(!bio.contains("bio/lecture-8"))
            let chem = try await h.tasks.tasks(course: "chem")
            #expect(chem.filter { $0.source.noteID == "bio/lecture-8" }.count == 2)
            #expect(chem.allSatisfy { $0.source.courseID == "chem" })
        }
    }

    // MARK: Updates (M7-02)

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    @Test(arguments: HarnessKind.allCases)
    func aTaskAddedFromOutsideIsInEveryViewWithinASecond(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let updates = h.tasks.updates
            let note = try await h.notes.open(id: "bio/glossary")
            let start = ContinuousClock.now
            try await h.editNote("bio/glossary", note.text + "\n- [ ] Book the lab @2026-09-28 ^t-book\n- [ ] Read ahead @2026-10-02 ^t-ahead\n")
            let update = await next(from: updates, timeout: 10)
            let elapsed = seconds(since: start)
            #expect(update == TaskUpdate(noteIDs: ["bio/glossary"], courseIDs: ["bio"]))
            #expect(elapsed < 1.0, "the update took \(elapsed) s")
            // By the time the update arrives, all three views show the task.
            #expect(try await h.tasks.today().contains { $0.id == "t-book" })
            #expect(try await h.tasks.upcoming().contains { $0.id == "t-ahead" })
            let bio = try await h.tasks.tasks(course: "bio")
            #expect(bio.contains { $0.id == "t-book" } && bio.contains { $0.id == "t-ahead" })
        }
    }

    @Test func aTaskAddedFromOutsideIsVisibleWithinASecondAtTheDefaultWatchInterval() async throws {
        try await withHarness(.vault, watchInterval: AppEnvironment.defaultWatchInterval) { h in
            let updates = h.tasks.updates
            let note = try await h.notes.open(id: "bio/glossary")
            let start = ContinuousClock.now
            try await h.editNote("bio/glossary", note.text + "\n- [ ] Book the lab @2026-09-28 ^t-book\n")
            let update = await next(from: updates, timeout: 10)
            let elapsed = seconds(since: start)
            print("M7-02: external edit -> TaskService.updates after \(elapsed) s (default watch interval \(AppEnvironment.defaultWatchInterval) s)")
            #expect(update?.noteIDs == ["bio/glossary"])
            #expect(elapsed < 1.0, "the update took \(elapsed) s")
            #expect(try await h.tasks.today().contains { $0.id == "t-book" })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func reopeningATaskFromOutsideIsAnUpdate(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let updates = h.tasks.updates
            let note = try await h.notes.open(id: "bio/assignments")
            // "Read chapter 6" is the one done task of the note.
            let reopened = note.text.replacingOccurrences(of: "- [x]", with: "- [ ]")
            #expect(reopened != note.text)
            try await h.editNote("bio/assignments", reopened)
            let update = await next(from: updates, timeout: 10)
            #expect(update?.noteIDs == ["bio/assignments"] && update?.courseIDs == ["bio"])
            #expect(try await h.tasks.tasks(course: "bio").filter { $0.source.noteID == "bio/assignments" }.allSatisfy { !$0.done })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func editsThatLeaveTheTasksAloneReportNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let updates = h.tasks.updates
            let glossary = try await h.notes.open(id: "bio/glossary")
            try await h.editNote("bio/glossary", glossary.text + "\nJust another paragraph.\n")   // prose only
            let lecture = try await h.notes.open(id: "bio/lecture-7")
            try await h.editNote("bio/lecture-7", lecture.text + "\n- [ ] Follow up ^t-follow\n")
            let update = await next(from: updates, timeout: 10)
            #expect(update?.noteIDs == ["bio/lecture-7"], "the prose edit must not be reported: \(String(describing: update))")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func writesThroughTheNoteRepositoryAreReportedDryRunsAreNot(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let updates = h.tasks.updates
            let a = try await h.notes.open(id: "bio/glossary")
            _ = try await h.notes.save(id: "bio/glossary", text: a.text + "\n- [ ] Never saved ^t-never\n", actor: .user,
                                       baseVersion: nil, dryRun: true, idempotencyKey: nil)
            _ = try await h.notes.save(id: "bio/glossary", text: a.text, actor: .user, baseVersion: nil, dryRun: false,
                                       idempotencyKey: nil)                                   // identical text
            let b = try await h.notes.open(id: "bio/lecture-7")
            _ = try await h.notes.save(id: "bio/lecture-7", text: b.text + "\n- [ ] Saved ^t-saved\n", actor: .user,
                                       baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let update = await next(from: updates, timeout: 10)
            #expect(update == TaskUpdate(noteIDs: ["bio/lecture-7"], courseIDs: ["bio"]))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aDeletedNoteReportsItsTasksAsChanged(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let updates = h.tasks.updates
            try await h.deleteNote("bio/lecture-8")
            let update = await next(from: updates, timeout: 10)
            #expect(update == TaskUpdate(noteIDs: ["bio/lecture-8"], courseIDs: ["bio"]))
            #expect(!(try await h.tasks.tasks(course: "bio")).contains { $0.source.noteID == "bio/lecture-8" })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aMovedNoteReportsBothCourses(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let updates = h.tasks.updates
            _ = try await h.notes.move(id: "bio/lecture-8", toCourse: "chem", actor: .user, baseVersion: nil,
                                       dryRun: false, idempotencyKey: nil)
            let update = await next(from: updates, timeout: 10)
            #expect(update == TaskUpdate(noteIDs: ["bio/lecture-8"], courseIDs: ["bio", "chem"]))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func everySubscriberGetsTheUpdateAndAFinishedEnvironmentEndsTheStream(kind: HarnessKind) async throws {
        let harness = try await Harness.make(kind)
        let first = harness.tasks.updates
        let second = harness.tasks.updates
        let note = try await harness.notes.open(id: "bio/glossary")
        try await harness.editNote("bio/glossary", note.text + "\n- [ ] Both hear this ^t-both\n")
        let a = await next(from: first, timeout: 10)
        let b = await next(from: second, timeout: 10)
        #expect(a != nil && a == b)
        await harness.shutdown()
        var ended = true
        let finished = await next(from: first, timeout: 5) { _ in true }
        if finished != nil { ended = false }
        #expect(ended)
    }
}
