import Foundation

/// Recording and undoing writes over the in-memory world (`FixtureChangeSetStore`).
///
/// Nothing in the write paths has to know about undo: after every non-dry write `record` compares the
/// world with the world after the previous write and keeps the difference, entity by entity (notes,
/// courses, inbox items, overrides, the archive flag), as the steps that undo the write. Outside
/// changes (`simulateExternal…`) are folded into the "previous" world, so they are never blamed on the
/// next write. Undo reverses the steps and checks, entity by entity, that each is still as the write
/// left it: the same rules as the vault journal, where the check is "the file still has the hash the
/// write gave it".
extension FixtureStore {
    /// Everything a write can change.
    struct World: Sendable {
        var notes: [NoteID: StoredNote]
        var courses: [Course]
        var overrides: [SessionOverride]
        var inbox: [InboxItem]
        var inboxStems: [String: String]
        var archived: Bool
    }

    enum NoteStep: Sendable { case created, deleted, moved, modified }

    /// One entity a write changed, with its state before and after.
    enum Step: Sendable {
        case note(NoteID, NoteStep, before: StoredNote?, after: StoredNote?)
        case course(CourseID, before: Course?, after: Course?)
        case inbox(String, before: InboxItem?, beforeStem: String?, after: InboxItem?)
        case overrides(before: [SessionOverride], after: [SessionOverride])
        case archived(before: Bool, after: Bool)
    }

    /// A recorded change set and the steps that undo it.
    struct Recorded: Sendable {
        var changeSet: ChangeSet
        var steps: [Step]
    }

    // MARK: World

    func currentWorld() -> World {
        World(notes: notes, courses: courses, overrides: overrides, inbox: inbox, inboxStems: inboxStems,
              archived: semester.isArchived)
    }

    /// Treats the current state as the baseline for the next recorded write.
    func syncWorld() { lastWorld = currentWorld() }

    /// Same file: bytes, place and name (the derived summary is not compared).
    static func sameState(_ a: StoredNote, _ b: StoredNote) -> Bool {
        sameBytes(a.content, b.content) && a.summary.courseID == b.summary.courseID && a.fileTitle == b.fileTitle
    }

    // MARK: Recording

    /// Keeps `changeSet` with the steps that reverse it (called by `finish` for every real write).
    func record(_ changeSet: ChangeSet) {
        let now = currentWorld()
        defer { lastWorld = now }
        guard !changeSet.entries.isEmpty, let last = lastWorld else { return }
        let steps = Self.steps(from: last, to: now)
        for case .note(_, _, let before, let after) in steps {
            for note in [before, after].compactMap({ $0 }) { versions.remember(note.content, version: Self.version(of: note.content)) }
        }
        guard !steps.isEmpty else { return }
        recorded.append(Recorded(changeSet: changeSet, steps: steps))
        prune()
    }

    static func steps(from old: World, to new: World) -> [Step] {
        var steps: [Step] = []
        for id in Set(old.notes.keys).union(new.notes.keys).sorted() {
            switch (old.notes[id], new.notes[id]) {
            case (nil, nil): continue
            case (nil, let n?): steps.append(.note(id, .created, before: nil, after: n))
            case (let o?, nil): steps.append(.note(id, .deleted, before: o, after: nil))
            case (let o?, let n?):
                if sameState(o, n) { continue }
                let moveOnly = sameBytes(o.content, n.content) && o.fileTitle == n.fileTitle && o.summary.courseID != n.summary.courseID
                steps.append(.note(id, moveOnly ? .moved : .modified, before: o, after: n))
            }
        }
        let oldCourses = Dictionary(uniqueKeysWithValues: old.courses.map { ($0.id, $0) })
        let newCourses = Dictionary(uniqueKeysWithValues: new.courses.map { ($0.id, $0) })
        for id in Set(oldCourses.keys).union(newCourses.keys).sorted() where oldCourses[id] != newCourses[id] {
            steps.append(.course(id, before: oldCourses[id], after: newCourses[id]))
        }
        let oldInbox = Dictionary(uniqueKeysWithValues: old.inbox.map { ($0.id, $0) })
        let newInbox = Dictionary(uniqueKeysWithValues: new.inbox.map { ($0.id, $0) })
        for id in Set(oldInbox.keys).union(newInbox.keys).sorted() where oldInbox[id] != newInbox[id] {
            steps.append(.inbox(id, before: oldInbox[id], beforeStem: old.inboxStems[id], after: newInbox[id]))
        }
        if old.overrides != new.overrides { steps.append(.overrides(before: old.overrides, after: new.overrides)) }
        if old.archived != new.archived { steps.append(.archived(before: old.archived, after: new.archived)) }
        return steps
    }

    func prune() {
        let drop = retention.dropCount(timestamps: recorded.map(\.changeSet.timestamp), now: clock.now)
        if drop > 0 { recorded.removeFirst(drop) }
    }

    // MARK: Reading

    /// Recorded change sets, newest first.
    func changes(limit: Int?) -> [ChangeSet] {
        prune()
        let all = recorded.reversed().map(\.changeSet)
        guard let limit else { return all }
        return Array(all.prefix(max(0, limit)))
    }

    func change(id: String) throws -> ChangeSet {
        prune()
        guard let r = recorded.first(where: { $0.changeSet.id == id }) else {
            throw MarginError.notFound("No change set \(id) (unknown or expired)")
        }
        return r.changeSet
    }

    // MARK: Undo

    private struct MergedNote { var current: String; var result: String }

    func undo(id: String, actor: Actor, mode: UndoMode, dryRun: Bool) throws -> ChangeSet {
        prune()
        guard let original = recorded.first(where: { $0.changeSet.id == id }) else {
            throw MarginError.notFound("No change set \(id) (unknown or expired)")
        }
        // Work on a copy: an undo that fails half way changes nothing.
        var world = currentWorld()
        let revertsArchive = original.steps.contains { if case .archived = $0 { return true } else { return false } }
        if world.archived && !revertsArchive {
            throw Self.undoConflict("\(semester.name) is archived and read-only", path: semester.name)
        }
        var merged: [NoteID: MergedNote] = [:]
        for step in original.steps.reversed() { try revert(step, in: &world, mode: mode, merged: &merged) }
        let entries = Self.inverted(original.changeSet.entries, merged: merged)
        if !dryRun { install(world) }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: nil, revertsID: id)
    }

    /// Puts `world` in place and tells listeners what changed on the catalog side.
    private func install(_ world: World) {
        let before = currentWorld()
        notes = world.notes
        courses = world.courses
        overrides = world.overrides
        inbox = world.inbox
        inboxStems = world.inboxStems
        setSemesterArchived(world.archived)

        var changed = Set<CourseID>()
        let old = Dictionary(uniqueKeysWithValues: before.courses.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: world.courses.map { ($0.id, $0) })
        for id in Set(old.keys).union(new.keys) where old[id] != new[id] { changed.insert(id) }
        if before.overrides != world.overrides {
            for o in Set(before.overrides).symmetricDifference(Set(world.overrides)) { changed.insert(o.courseID) }
        }
        if before.archived != world.archived { changed.formUnion(world.courses.map(\.id)) }
        if !changed.isEmpty { catalogUpdates.send(CatalogUpdate(courses: changed.sorted())) }
        let examCourses = changed.filter { old[$0]?.exams != new[$0]?.exams }.sorted()
        if !examCourses.isEmpty { taskChanges.send(TaskUpdate(noteIDs: [], courseIDs: examCourses)) }
    }

    private func revert(_ step: Step, in world: inout World, mode: UndoMode, merged: inout [NoteID: MergedNote]) throws {
        switch step {
        case .note(let id, let kind, let before, let after):
            switch kind {
            case .created:
                guard let after, let cur = world.notes[id], Self.sameState(cur, after) else {
                    throw Self.undoConflict("\(id) changed or disappeared after it was created",
                                            path: after.map { path(of: $0) } ?? id, current: world.notes[id].map { Self.version(of: $0.content) })
                }
                world.notes[id] = nil
            case .deleted:
                guard let before, world.notes[id] == nil,
                      !fileNameTaken(before.fileTitle, in: before.summary.courseID ?? "", except: nil, in: world.notes) else {
                    throw Self.undoConflict("\(id) exists again, it cannot be restored over it",
                                            path: before.map { path(of: $0) } ?? id, current: world.notes[id].map { Self.version(of: $0.content) })
                }
                world.notes[id] = before
            case .moved:
                guard let before, let after, var cur = world.notes[id], cur.summary.courseID == after.summary.courseID else {
                    throw Self.undoConflict("\(id) is not where the move left it", path: after.map { path(of: $0) } ?? id)
                }
                guard !fileNameTaken(before.fileTitle, in: before.summary.courseID ?? "", except: id, in: world.notes) else {
                    throw Self.undoConflict("\(before.summary.courseID ?? "") already has a note named \(before.fileTitle)",
                                            path: path(of: before))
                }
                cur.summary.courseID = before.summary.courseID
                world.notes[id] = cur
            case .modified:
                guard let before, let after, let cur = world.notes[id] else {
                    throw Self.undoConflict("\(id) no longer exists", path: (before ?? after).map { path(of: $0) } ?? id)
                }
                let curVersion = Self.version(of: cur.content)
                if Self.sameState(cur, after) {
                    world.notes[id] = before
                } else if mode == .merge {
                    let r = ThreeWayMerge.merge(base: after.content, ours: before.content, theirs: cur.content,
                                                oursLabel: "undone", theirsLabel: "stored")
                    guard !r.hasConflicts else {
                        throw Self.undoConflict("\(id) was edited in the same place after this change",
                                                path: path(of: cur), current: curVersion, merged: r)
                    }
                    var restored = cur
                    let parsed = Frontmatter.parse(r.text)
                    restored.frontmatter = parsed.frontmatter
                    restored.body = parsed.body
                    restored.summary = summarize(restored)
                    world.notes[id] = restored
                    merged[id] = MergedNote(current: curVersion, result: Self.version(of: restored.content))
                } else {
                    throw Self.undoConflict("\(id) changed after this change", path: path(of: cur), current: curVersion)
                }
            }
        case .course(let id, let before, let after):
            let current = world.courses.first { $0.id == id }
            guard current == after else {
                throw Self.undoConflict("course \(id) changed after this change", path: "course:\(id)")
            }
            world.courses.removeAll { $0.id == id }
            if let before { world.courses.append(before) }
        case .inbox(let id, let before, let beforeStem, let after):
            let current = world.inbox.first { $0.id == id }
            guard current == after else {
                throw Self.undoConflict("inbox item \(id) changed after this change", path: "\(CaptureRules.inboxFolder)/\(id).md")
            }
            world.inbox.removeAll { $0.id == id }
            world.inboxStems[id] = nil
            if let before { world.inbox.append(before); world.inboxStems[id] = beforeStem }
        case .overrides(let before, let after):
            guard world.overrides == after else {
                throw Self.undoConflict("the class overrides changed after this change", path: "overrides")
            }
            world.overrides = before
        case .archived(let before, let after):
            guard world.archived == after else {
                throw Self.undoConflict("the semester was archived or restored again after this change", path: semester.name)
            }
            world.archived = before
        }
    }

    private static func undoConflict(_ message: String, path: String, current: String? = nil,
                                     merged: ThreeWayMerge.Result? = nil) -> MarginError {
        .conflict("Cannot undo: \(message)",
                  ConflictDetail(path: path, currentVersion: current, mergedText: merged?.text,
                                 conflictCount: merged?.conflictCount))
    }

    /// The entries that describe reversing `entries` (last first).
    private static func inverted(_ entries: [ChangeSet.Entry], merged: [NoteID: MergedNote]) -> [ChangeSet.Entry] {
        entries.reversed().map { e in
            var out: ChangeSet.Entry
            switch e.kind {
            case .created: out = .init(path: e.path, kind: .deleted, noteID: e.noteID, beforeHash: e.afterHash)
            case .deleted: out = .init(path: e.path, kind: .created, noteID: e.noteID, afterHash: e.beforeHash)
            case .modified: out = .init(path: e.path, kind: .modified, noteID: e.noteID, beforeHash: e.afterHash, afterHash: e.beforeHash)
            case .moved:
                out = .init(path: e.fromPath ?? e.path, kind: .moved, noteID: e.noteID, fromPath: e.path,
                            beforeHash: e.afterHash, afterHash: e.beforeHash)
            }
            if e.kind == .modified, let id = e.noteID, let m = merged[id] {
                out.beforeHash = m.current; out.afterHash = m.result; out.merged = true
            }
            return out
        }
    }
}
