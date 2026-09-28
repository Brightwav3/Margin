import Foundation

/// The in-memory world behind the `Fixture…` services: courses, notes (with markdown bodies) and
/// everything derived from them. Typed data comes from `Fixtures.week5`; note bodies from
/// `FixtureWorld.markdownBody(of:)`. Writes change this state only, and follow the same rules as
/// the vault implementation (`baseVersion` → `.conflict`, `dryRun` changes nothing, idempotency
/// keys, trash on delete).
///
/// Known difference to the vault: modification times (`NoteSummary.modified`) are stamped from the
/// clock on every write here; the vault implementation does not report them yet.
actor FixtureStore {
    /// What one write did to one note, with the states needed to reverse it.
    enum Step: Sendable {
        case modified(before: StoredNote, after: StoredNote)
        case created(after: StoredNote)
        case deleted(before: StoredNote)
        case moved(before: StoredNote, after: StoredNote)
    }

    /// A recorded change set and the steps that undo it.
    struct Recorded: Sendable {
        var changeSet: ChangeSet
        var steps: [Step]
    }

    struct StoredNote: Sendable {
        var summary: NoteSummary
        /// The title the file is named after; the heading may differ.
        var fileTitle: String
        var body: String
    }

    let semester: Semester
    let clock: any Clock
    private(set) var courses: [Course]
    private var notes: [NoteID: StoredNote] = [:]
    private var changeSets: ChangeSetFactory
    private var idempotency = IdempotencyCache()
    private var versions = TextVersionCache()
    private var recorded: [Recorded] = []
    private let retention: ChangeSetRetention
    private let extractor: TaskExtractor
    private let scanner = MarkdownScanner()

    nonisolated let noteChanges = Broadcaster<[NoteChange]>()
    nonisolated let catalogUpdates = Broadcaster<CatalogUpdate>()

    init(world: FixtureWorld, clock: any Clock, retention: ChangeSetRetention = .standard) {
        self.semester = world.semester
        self.clock = clock
        self.retention = retention
        self.courses = world.courses
        self.changeSets = ChangeSetFactory(clock: clock)
        self.extractor = TaskExtractor(clock: clock)
        for summary in world.allNotes {
            notes[summary.id] = StoredNote(summary: summary, fileTitle: summary.title,
                                           body: world.markdownBody(of: summary.id) ?? "# \(summary.title)\n")
        }
    }

    // MARK: Courses

    func semesters() -> [Semester] { [semester] }

    func courses(query: String?) -> [Course] {
        ServiceRules.sortCourses(courses.filter { ServiceRules.matches($0, query: query) })
    }

    func course(id: CourseID) throws -> Course {
        guard let c = courses.first(where: { $0.id == id }) else { throw MarginError.notFound("No course \(id)") }
        return c
    }

    func sessions(week: Int) throws -> [SessionOccurrence] {
        try ServiceRules.occurrences(week: week, semester: semester, courses: courses)
    }

    // MARK: Notes (read)

    func notes(course: CourseID?) throws -> [NoteSummary] {
        if let course { _ = try self.course(id: course) }
        return ServiceRules.sortNotes(notes.values.map(\.summary).filter { course == nil || $0.courseID == course })
    }

    func open(id: NoteID) throws -> Note {
        guard let n = notes[id] else { throw MarginError.notFound("No note \(id)") }
        let version = Self.version(of: n.body)
        versions.remember(n.body, version: version)
        return Note(summary: n.summary, text: n.body, version: version)
    }

    // MARK: Tasks (read)

    private func extractTasks(of note: StoredNote) -> [TaskItem] {
        extractor.extract(from: note.body).map {
            extractor.taskItem($0, noteID: note.summary.id, courseID: note.summary.courseID)
        }
    }

    func today() -> [TaskItem] {
        ServiceRules.todayItems(tasks: allTasks(), exams: ServiceRules.examItems(courses), today: clock.today)
    }

    func upcoming() -> [TaskItem] {
        ServiceRules.upcomingItems(tasks: allTasks(), exams: ServiceRules.examItems(courses), today: clock.today)
    }

    func tasks(course id: CourseID) throws -> [TaskItem] {
        _ = try course(id: id)
        let items = notes.values.filter { $0.summary.courseID == id }.flatMap { extractTasks(of: $0) }
        return ServiceRules.courseTasks(items, today: clock.today)
    }

    private func allTasks() -> [TaskItem] {
        notes.values.filter { $0.summary.courseID != nil }.flatMap { extractTasks(of: $0) }
    }

    // MARK: Notes (write)

    func save(id: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard var note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        let before = note
        let current = Self.version(of: note.body)
        var newText = text
        var merged = false
        if let base = baseVersion, base != current {
            // A stale base: merge when the two sides changed different lines, else conflict.
            guard let baseText = versions.lookup(base) else {
                throw MarginError.conflict("Note \(id) changed since version \(base.prefix(12)) (now \(current.prefix(12)))",
                                           ConflictDetail(path: path(of: note), currentVersion: current))
            }
            let result = ThreeWayMerge.merge(base: baseText, ours: text, theirs: note.body,
                                             oursLabel: "yours", theirsLabel: "stored")
            if result.hasConflicts {
                throw MarginError.conflict(
                    "Note \(id) changed since version \(base.prefix(12)) in the same place",
                    ConflictDetail(path: path(of: note), currentVersion: current, mergedText: result.text,
                                   conflictCount: result.conflictCount))
            }
            newText = result.text
            merged = true
        }
        var entries: [ChangeSet.Entry] = []
        var steps: [Step] = []
        if !sameBytes(newText, note.body) {
            note.body = newText
            note.summary = summarize(note)
            entries = [.init(path: path(of: note), kind: .modified, noteID: id, beforeHash: current,
                             afterHash: Self.version(of: newText), merged: merged ? true : nil)]
            steps = [.modified(before: before, after: note)]
            if !dryRun { notes[id] = note; versions.remember(newText, version: Self.version(of: newText)) }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey, steps: steps)
    }

    func create(course courseID: CourseID, title: String, kind: NoteKind, text: String, actor: Actor,
                dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let course = try self.course(id: courseID)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw MarginError.invalid("A note needs a title") }
        let id = ServiceRules.noteID(course: courseID, title: title)
        guard notes[id] == nil, !fileNameTaken(title, in: courseID, except: nil) else {
            throw MarginError.conflict("A note named \(title) already exists in \(course.name)")
        }
        var note = StoredNote(
            summary: NoteSummary(id: id, courseID: courseID, title: title, kind: kind),
            fileTitle: title, body: ServiceRules.initialBody(title: title, text: text))
        note.summary = summarize(note)
        let entry = ChangeSet.Entry(path: path(of: note), kind: .created, noteID: id, afterHash: Self.version(of: note.body))
        if !dryRun { notes[id] = note; versions.remember(note.body, version: Self.version(of: note.body)) }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey, steps: [.created(after: note)])
    }

    func move(id: NoteID, toCourse target: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard var note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        _ = try course(id: target)
        let version = Self.version(of: note.body)
        try requireBaseVersion(baseVersion, matches: version, what: "Note \(id)", path: path(of: note))
        var entries: [ChangeSet.Entry] = []
        var steps: [Step] = []
        if note.summary.courseID != target {
            guard !fileNameTaken(note.fileTitle, in: target, except: id) else {
                throw MarginError.conflict("\(target) already has a note named \(note.fileTitle)")
            }
            let before = note
            let old = path(of: note)
            note.summary.courseID = target
            entries = [.init(path: path(of: note), kind: .moved, noteID: id, fromPath: old, beforeHash: version, afterHash: version)]
            steps = [.moved(before: before, after: note)]
            if !dryRun { notes[id] = note }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey, steps: steps)
    }

    func delete(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        let version = Self.version(of: note.body)
        try requireBaseVersion(baseVersion, matches: version, what: "Note \(id)", path: path(of: note))
        let entry = ChangeSet.Entry(path: path(of: note), kind: .deleted, noteID: id, beforeHash: version)
        if !dryRun { notes[id] = nil }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey, steps: [.deleted(before: note)])
    }

    // MARK: Change sets (undo)

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

    func undo(id: String, actor: Actor, mode: UndoMode, dryRun: Bool) throws -> ChangeSet {
        prune()
        guard let original = recorded.first(where: { $0.changeSet.id == id }) else {
            throw MarginError.notFound("No change set \(id) (unknown or expired)")
        }
        // Work on a copy: an undo that fails half way changes nothing.
        var work = notes
        var inverse: [Step] = []
        var entries: [ChangeSet.Entry] = []
        for step in original.steps.reversed() {
            switch step {
            case .modified(let before, let after):
                guard let cur = work[before.summary.id] else {
                    throw undoConflict("\(before.summary.id) no longer exists", path: path(of: before), current: nil)
                }
                let curVersion = Self.version(of: cur.body)
                if curVersion == Self.version(of: after.body) {
                    work[before.summary.id] = before
                    inverse.append(.modified(before: cur, after: before))
                    entries.append(.init(path: path(of: before), kind: .modified, noteID: before.summary.id,
                                         beforeHash: curVersion, afterHash: Self.version(of: before.body)))
                } else if mode == .merge {
                    let r = ThreeWayMerge.merge(base: after.body, ours: before.body, theirs: cur.body,
                                                oursLabel: "undone", theirsLabel: "stored")
                    guard !r.hasConflicts else {
                        throw undoConflict("\(before.summary.id) was edited in the same place after this change",
                                           path: path(of: cur), current: curVersion, merged: r)
                    }
                    var restored = cur
                    restored.body = r.text
                    restored.summary = summarize(restored)
                    work[before.summary.id] = restored
                    inverse.append(.modified(before: cur, after: restored))
                    entries.append(.init(path: path(of: restored), kind: .modified, noteID: before.summary.id,
                                         beforeHash: curVersion, afterHash: Self.version(of: r.text), merged: true))
                } else {
                    throw undoConflict("\(before.summary.id) changed after this change", path: path(of: cur), current: curVersion)
                }
            case .created(let after):
                guard let cur = work[after.summary.id], Self.version(of: cur.body) == Self.version(of: after.body) else {
                    throw undoConflict("\(after.summary.id) changed or disappeared after it was created",
                                       path: path(of: after), current: work[after.summary.id].map { Self.version(of: $0.body) })
                }
                work[after.summary.id] = nil
                inverse.append(.deleted(before: cur))
                entries.append(.init(path: path(of: cur), kind: .deleted, noteID: cur.summary.id,
                                     beforeHash: Self.version(of: cur.body)))
            case .deleted(let before):
                guard work[before.summary.id] == nil,
                      !fileNameTaken(before.fileTitle, in: before.summary.courseID ?? "", except: nil, in: work) else {
                    throw undoConflict("\(before.summary.id) exists again, it cannot be restored over it",
                                       path: path(of: before), current: work[before.summary.id].map { Self.version(of: $0.body) })
                }
                work[before.summary.id] = before
                inverse.append(.created(after: before))
                entries.append(.init(path: path(of: before), kind: .created, noteID: before.summary.id,
                                     afterHash: Self.version(of: before.body)))
            case .moved(let before, let after):
                guard let cur = work[after.summary.id], cur.summary.courseID == after.summary.courseID else {
                    throw undoConflict("\(after.summary.id) is not where the move left it", path: path(of: after), current: nil)
                }
                guard !fileNameTaken(before.fileTitle, in: before.summary.courseID ?? "", except: before.summary.id, in: work) else {
                    throw undoConflict("\(before.summary.courseID ?? "") already has a note named \(before.fileTitle)",
                                       path: path(of: before), current: nil)
                }
                var back = cur
                back.summary.courseID = before.summary.courseID
                work[after.summary.id] = back
                inverse.append(.moved(before: cur, after: back))
                let v = Self.version(of: cur.body)
                entries.append(.init(path: path(of: back), kind: .moved, noteID: back.summary.id,
                                     fromPath: path(of: cur), beforeHash: v, afterHash: v))
            }
        }
        if !dryRun {
            notes = work
            for step in inverse {
                switch step {
                case .modified(_, let n), .created(let n), .deleted(let n), .moved(_, let n):
                    versions.remember(n.body, version: Self.version(of: n.body))
                }
            }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: nil, steps: inverse, revertsID: id)
    }

    private func undoConflict(_ message: String, path: String, current: String?,
                              merged: ThreeWayMerge.Result? = nil) -> MarginError {
        .conflict("Cannot undo: \(message)",
                  ConflictDetail(path: path, currentVersion: current, mergedText: merged?.text,
                                 conflictCount: merged?.conflictCount))
    }

    private func prune() {
        let drop = retention.dropCount(timestamps: recorded.map(\.changeSet.timestamp), now: clock.now)
        if drop > 0 { recorded.removeFirst(drop) }
    }

    // MARK: Simulated outside changes (tests, previews)

    /// Replaces a note's body as if another program had edited the file.
    func simulateExternalEdit(id: NoteID, text: String) throws {
        guard var note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        note.body = text
        note.summary = summarize(note)
        notes[id] = note
        versions.remember(text, version: Self.version(of: text))
        noteChanges.send([NoteChange(noteID: id, kind: .modified)])
    }

    func simulateExternalCreate(course: CourseID, title: String, text: String) throws -> NoteID {
        _ = try self.course(id: course)
        let id = ServiceRules.noteID(course: course, title: title)
        var note = StoredNote(summary: NoteSummary(id: id, courseID: course, title: title), fileTitle: title,
                              body: ServiceRules.initialBody(title: title, text: text))
        note.summary = summarize(note)
        notes[id] = note
        noteChanges.send([NoteChange(noteID: id, kind: .created)])
        return id
    }

    func simulateExternalDelete(id: NoteID) throws {
        guard notes[id] != nil else { throw MarginError.notFound("No note \(id)") }
        notes[id] = nil
        noteChanges.send([NoteChange(noteID: id, kind: .deleted)])
    }

    /// Changes a course as if `_course.md` had been edited elsewhere.
    func simulateExternalCourseEdit(id: CourseID, _ change: @Sendable (inout Course) -> Void) throws {
        guard let i = courses.firstIndex(where: { $0.id == id }) else { throw MarginError.notFound("No course \(id)") }
        change(&courses[i])
        catalogUpdates.send(CatalogUpdate(courses: [id]))
    }

    // MARK: Helpers

    static func version(of body: String) -> String { ContentHash(of: body).hex }

    private func finish(actor: Actor, entries: [ChangeSet.Entry], dryRun: Bool, key: String?,
                        steps: [Step], revertsID: String? = nil) -> ChangeSet {
        var cs = changeSets.make(actor: actor, entries: entries, isDryRun: dryRun, idempotencyKey: key)
        cs.revertsID = revertsID
        if !dryRun {
            idempotency.remember(cs, actor: actor)
            if !entries.isEmpty {
                recorded.append(Recorded(changeSet: cs, steps: steps))
                prune()
            }
        }
        return cs
    }

    private func path(of note: StoredNote) -> String {
        guard let id = note.summary.courseID, let course = courses.first(where: { $0.id == id }) else {
            return VaultPath.filename(fromTitle: note.fileTitle) + ".md"
        }
        return ServiceRules.notePath(semester: semester, course: course, fileTitle: note.fileTitle)
    }

    private func fileNameTaken(_ title: String, in course: CourseID, except id: NoteID?,
                               in world: [NoteID: StoredNote]? = nil) -> Bool {
        let name = VaultPath.filename(fromTitle: title)
        return (world ?? notes).values.contains {
            $0.summary.courseID == course && $0.summary.id != id && VaultPath.filename(fromTitle: $0.fileTitle) == name
        }
    }

    /// Recomputes what the index would derive from the body.
    private func summarize(_ note: StoredNote) -> NoteSummary {
        var s = note.summary
        let scan = scanner.scan(note.body)
        let h1 = scan.headings.first { $0.level == 1 }?.text
        s.title = (h1?.isEmpty == false ? h1 : nil) ?? note.fileTitle
        let tasks = extractor.extract(from: scan)
        s.totalTasks = tasks.count
        s.openTasks = tasks.filter { !$0.done }.count
        s.wordCount = NoteIndex.wordCount(note.body)
        s.snippet = NoteIndex.snippet(note.body)
        s.imageCount = scan.links.filter { $0.isEmbed && NoteIndex.isImage($0.inner) }.count
        s.isPlaceholder = false
        s.modified = clock.localDateTime(from: clock.now)
        return s
    }
}
