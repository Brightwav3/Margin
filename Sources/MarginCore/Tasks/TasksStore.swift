import Foundation

/// The tasks of one note as the store last saw them; the unit of change tracking.
struct TaskSnapshotEntry: Sendable, Hashable {
    var noteID: NoteID
    var courseID: CourseID?
    /// Without `label`: a label depends on the clock, not on the file.
    var tasks: [TaskItem]

    init(noteID: NoteID, courseID: CourseID?, tasks: [TaskItem]) {
        self.noteID = noteID; self.courseID = courseID
        self.tasks = tasks.map { var t = $0; t.label = nil; return t }
    }
}

/// Finds what changed between two snapshots (shared by the vault and fixture implementations so
/// they report the same updates).
enum TaskDiff {
    /// The update for the differences, or `nil` when no note's tasks changed. A note without tasks
    /// counts the same as a missing note, so writing prose to a task-free note reports nothing.
    static func update<Key: Hashable>(old: [Key: TaskSnapshotEntry], new: [Key: TaskSnapshotEntry]) -> TaskUpdate? {
        var notes: [NoteID] = []
        var courses: [CourseID] = []
        for key in Set(old.keys).union(new.keys) {
            let before = old[key].flatMap { $0.tasks.isEmpty ? nil : $0 }
            let after = new[key].flatMap { $0.tasks.isEmpty ? nil : $0 }
            guard before != after else { continue }
            for entry in [before, after].compactMap({ $0 }) {
                notes.append(entry.noteID)
                if let c = entry.courseID { courses.append(c) }
            }
        }
        return notes.isEmpty ? nil : TaskUpdate(noteIDs: notes, courseIDs: courses)
    }
}

/// The tasks of a vault, derived from the `NoteIndex`, with change tracking (M7-02).
///
/// Reads go straight to the index (which the watcher and the app's own writes keep current). After
/// every batch of changes the owner calls `reconcile`; the store compares the tasks of the touched
/// notes with what it saw before and publishes a `TaskUpdate` on `updates` when they differ. The
/// chain for an edit made by another program is: file watcher → index → `reconcile` → `updates`.
actor TasksStore {
    private let index: NoteIndex
    private var snapshot: [String: TaskSnapshotEntry] = [:]

    /// Fans updates out to `TaskService.updates` subscribers.
    nonisolated let updates = Broadcaster<TaskUpdate>()

    init(index: NoteIndex) { self.index = index }

    /// The course of a note record (from the vault's course model).
    typealias CourseResolver = @Sendable (NoteRecord) -> CourseID?

    /// Takes the first snapshot; nothing is published.
    func prime(courseOf: CourseResolver) async {
        snapshot = await currentEntries(paths: nil, courseOf: courseOf)
    }

    /// Every task of every note that has a course, optionally of one course.
    func allTasks(courseOf: CourseResolver, course: CourseID? = nil) async -> [TaskItem] {
        var items: [TaskItem] = []
        for r in await index.allNotes where VaultBackend.isNotePath(r.path) {
            guard let cid = courseOf(r), course == nil || cid == course else { continue }
            items += r.tasks.map { var t = $0; t.source.courseID = cid; return t }
        }
        return items
    }

    /// Compares the tasks of `paths` (all notes when `nil`) with the last snapshot, remembers the
    /// new state and publishes what changed.
    @discardableResult
    func reconcile(paths: [String]?, courseOf: CourseResolver) async -> TaskUpdate? {
        let fresh = await currentEntries(paths: paths, courseOf: courseOf)
        let old = snapshot
        var new = snapshot
        if let paths {
            for p in paths { new[p] = nil }
        } else {
            new = [:]
        }
        for (p, e) in fresh { new[p] = e }
        snapshot = new
        guard let update = TaskDiff.update(old: old, new: new) else { return nil }
        updates.send(update)
        return update
    }

    /// Publishes a change that is not in any note, such as new exam dates.
    func publish(courses: [CourseID]) {
        guard !courses.isEmpty else { return }
        updates.send(TaskUpdate(noteIDs: [], courseIDs: courses))
    }

    private func currentEntries(paths: [String]?, courseOf: CourseResolver) async -> [String: TaskSnapshotEntry] {
        var result: [String: TaskSnapshotEntry] = [:]
        var records: [NoteRecord] = []
        if let paths {
            for p in Set(paths) { if let r = await index.note(byPath: p) { records.append(r) } }
        } else {
            records = await index.allNotes
        }
        for r in records where VaultBackend.isNotePath(r.path) {
            guard let cid = courseOf(r) else { continue }
            result[r.path] = TaskSnapshotEntry(
                noteID: r.id, courseID: cid,
                tasks: r.tasks.map { var t = $0; t.source.courseID = cid; return t })
        }
        return result
    }
}
