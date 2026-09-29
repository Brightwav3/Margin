import Foundation
import Testing
@testable import MarginCore

@Suite struct TasksStoreTests {
    typealias S = TaskQueryTestSupport

    private func entry(_ note: NoteID, course: CourseID? = "bio", lines: [Int] = [3], done: Bool = false,
                       label: DueLabel? = nil) -> TaskSnapshotEntry {
        TaskSnapshotEntry(noteID: note, courseID: course, tasks: lines.map {
            TaskItem(id: "t-\($0)", text: "Task \($0)", due: nil, label: label, done: done,
                     source: TaskLocation(noteID: note, line: $0, courseID: course))
        })
    }

    // MARK: TaskDiff

    @Test func identicalSnapshotsAreQuiet() {
        let s = ["a.md": entry("a"), "b.md": entry("b", lines: [])]
        #expect(TaskDiff.update(old: s, new: s) == nil)
    }

    @Test func labelsDoNotCount() {
        let old = ["a.md": entry("a", label: .today)]
        let new = ["a.md": entry("a", label: .overdue(days: 3))]
        #expect(TaskDiff.update(old: old, new: new) == nil)
    }

    @Test func anEmptyNoteIsTheSameAsNoNote() {
        #expect(TaskDiff.update(old: [:], new: ["a.md": entry("a", lines: [])]) == nil)
        #expect(TaskDiff.update(old: ["a.md": entry("a", lines: [])], new: [:]) == nil)
    }

    @Test func addedRemovedTickedAndShiftedTasksAreChanges() {
        let base = ["a.md": entry("a")]
        #expect(TaskDiff.update(old: [:], new: base) == TaskUpdate(noteIDs: ["a"], courseIDs: ["bio"]))
        #expect(TaskDiff.update(old: base, new: [:]) == TaskUpdate(noteIDs: ["a"], courseIDs: ["bio"]))
        #expect(TaskDiff.update(old: base, new: ["a.md": entry("a", done: true)])?.noteIDs == ["a"])
        #expect(TaskDiff.update(old: base, new: ["a.md": entry("a", lines: [5])])?.noteIDs == ["a"])
        #expect(TaskDiff.update(old: base, new: ["a.md": entry("a", lines: [3, 9])])?.noteIDs == ["a"])
    }

    @Test func aMoveToAnotherCourseNamesBoth() {
        let old = ["x/a.md": entry("a", course: "bio")]
        let new = ["y/a.md": entry("a", course: "chem", lines: [3])]
        #expect(TaskDiff.update(old: old, new: new) == TaskUpdate(noteIDs: ["a"], courseIDs: ["bio", "chem"]))
    }

    @Test func updatesAreSortedAndDeduplicated() {
        let u = TaskUpdate(noteIDs: ["b", "a", "b"], courseIDs: ["z", "m", "z"])
        #expect(u.noteIDs == ["a", "b"] && u.courseIDs == ["m", "z"])
    }

    @Test func updateEncodesStably() throws {
        let data = try JSONEncoder().encode(TaskUpdate(noteIDs: ["a"], courseIDs: ["bio"]))
        let back = try JSONDecoder().decode(TaskUpdate.self, from: data)
        #expect(back == TaskUpdate(noteIDs: ["a"], courseIDs: ["bio"]))
    }

    // MARK: TasksStore over a NoteIndex

    private let resolver: TasksStore.CourseResolver = { $0.courseID }

    private func note(_ tasks: String) -> String { "---\nid: n1\n---\n# Note\n\nSome prose.\n\n\(tasks)\n" }

    @Test func reconcileReportsOnlyRealTaskChanges() async throws {
        let index = NoteIndex(clock: FixedClock())
        await index.update(path: "Fall/Bio/n.md", content: note("- [ ] One ^t-1"))
        await index.update(path: "Fall/Bio/other.md", content: "# Other\n\n- [ ] Elsewhere ^t-9\n")
        let store = TasksStore(index: index)
        await store.prime(courseOf: resolver)
        let updates = store.updates.subscribe()

        // Nothing changed.
        #expect(await store.reconcile(paths: ["Fall/Bio/n.md"], courseOf: resolver) == nil)
        // Prose only.
        await index.update(path: "Fall/Bio/n.md", content: note("- [ ] One ^t-1").replacingOccurrences(of: "Some prose.", with: "Other prose."))
        #expect(await store.reconcile(paths: ["Fall/Bio/n.md"], courseOf: resolver) == nil)
        // A tick.
        await index.update(path: "Fall/Bio/n.md", content: note("- [x] One ^t-1"))
        let tick = await store.reconcile(paths: ["Fall/Bio/n.md"], courseOf: resolver)
        #expect(tick == TaskUpdate(noteIDs: ["n1"], courseIDs: ["Bio"]))
        // The published update is the returned one, and only one was published.
        let seen = await first(of: updates)
        #expect(seen == tick)
        // A note deleted.
        await index.remove(path: "Fall/Bio/other.md")
        #expect(await store.reconcile(paths: ["Fall/Bio/other.md"], courseOf: resolver)?.noteIDs == ["Fall/Bio/other"])
    }

    @Test func reconcileAllFindsChangesInAnyNote() async throws {
        let index = NoteIndex(clock: FixedClock())
        await index.update(path: "Fall/Bio/n.md", content: note("- [ ] One ^t-1"))
        let store = TasksStore(index: index)
        await store.prime(courseOf: resolver)
        await index.update(path: "Fall/Bio/n.md", content: note("- [ ] One ^t-1\n- [ ] Two ^t-2"))
        #expect(await store.reconcile(paths: nil, courseOf: resolver)?.noteIDs == ["n1"])
        #expect(await store.reconcile(paths: nil, courseOf: resolver) == nil)
    }

    @Test func aCourseResolverChangeMovesTasksBetweenCourses() async throws {
        let index = NoteIndex(clock: FixedClock())
        await index.update(path: "Fall/Bio/n.md", content: note("- [ ] One ^t-1"))
        let store = TasksStore(index: index)
        await store.prime(courseOf: resolver)
        let renamed: TasksStore.CourseResolver = { _ in "life-science" }
        let u = await store.reconcile(paths: nil, courseOf: renamed)
        #expect(u == TaskUpdate(noteIDs: ["n1"], courseIDs: ["Bio", "life-science"]))
        let tasks = await store.allTasks(courseOf: renamed, course: "life-science")
        #expect(tasks.map(\.source.courseID) == ["life-science"])
        #expect(await store.allTasks(courseOf: renamed, course: "Bio").isEmpty)
    }

    @Test func notesWithoutACourseHaveNoTasksInTheStore() async throws {
        let index = NoteIndex(clock: FixedClock())
        await index.update(path: "loose.md", content: "# Loose\n\n- [ ] Orphan\n")
        let store = TasksStore(index: index)
        await store.prime(courseOf: { _ in nil })
        #expect(await store.allTasks(courseOf: { _ in nil }).isEmpty)
    }

    @Test func publishSendsExamOnlyChanges() async throws {
        let store = TasksStore(index: NoteIndex(clock: FixedClock()))
        let updates = store.updates.subscribe()
        await store.publish(courses: [])
        await store.publish(courses: ["bio"])
        #expect(await first(of: updates) == TaskUpdate(noteIDs: [], courseIDs: ["bio"]))
    }
}

/// The first element of `stream`, or `nil` after 5 seconds.
private func first(of stream: AsyncStream<TaskUpdate>) async -> TaskUpdate? {
    await withTaskGroup(of: TaskUpdate?.self) { group in
        group.addTask { for await u in stream { return u }; return nil }
        group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000); return nil }
        let r = await group.next() ?? nil
        group.cancelAll()
        return r
    }
}
