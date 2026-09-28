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
    struct StoredNote {
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
    private let extractor: TaskExtractor
    private let scanner = MarkdownScanner()

    nonisolated let noteChanges = Broadcaster<[NoteChange]>()
    nonisolated let catalogUpdates = Broadcaster<CatalogUpdate>()

    init(world: FixtureWorld, clock: any Clock) {
        self.semester = world.semester
        self.clock = clock
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
        return Note(summary: n.summary, text: n.body, version: Self.version(of: n.body))
    }

    // MARK: Tasks (read)

    private func extractTasks(of note: StoredNote) -> [TaskItem] {
        extractor.extract(from: note.body).map {
            extractor.taskItem($0, noteID: note.summary.id, courseID: note.summary.courseID)
        }
    }

    func today() -> [TaskItem] {
        ServiceRules.todayItems(tasks: allTasks(), exams: ServiceRules.examItems(courses), clock: clock)
    }

    func upcoming() -> [TaskItem] {
        ServiceRules.upcomingItems(tasks: allTasks(), exams: ServiceRules.examItems(courses), clock: clock)
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
        let current = Self.version(of: note.body)
        try requireBaseVersion(baseVersion, matches: current, what: "Note \(id)")
        var entries: [ChangeSet.Entry] = []
        if text != note.body {
            entries = [.init(path: path(of: note), kind: .modified, noteID: id, beforeHash: current, afterHash: Self.version(of: text))]
            note.body = text
            note.summary = summarize(note)
            if !dryRun { notes[id] = note }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
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
        if !dryRun { notes[id] = note }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }

    func move(id: NoteID, toCourse target: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard var note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        _ = try course(id: target)
        let version = Self.version(of: note.body)
        try requireBaseVersion(baseVersion, matches: version, what: "Note \(id)")
        var entries: [ChangeSet.Entry] = []
        if note.summary.courseID != target {
            guard !fileNameTaken(note.fileTitle, in: target, except: id) else {
                throw MarginError.conflict("\(target) already has a note named \(note.fileTitle)")
            }
            let old = path(of: note)
            note.summary.courseID = target
            entries = [.init(path: path(of: note), kind: .moved, noteID: id, fromPath: old, beforeHash: version, afterHash: version)]
            if !dryRun { notes[id] = note }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func delete(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        let version = Self.version(of: note.body)
        try requireBaseVersion(baseVersion, matches: version, what: "Note \(id)")
        let entry = ChangeSet.Entry(path: path(of: note), kind: .deleted, noteID: id, beforeHash: version)
        if !dryRun { notes[id] = nil }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }

    // MARK: Simulated outside changes (tests, previews)

    /// Replaces a note's body as if another program had edited the file.
    func simulateExternalEdit(id: NoteID, text: String) throws {
        guard var note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        note.body = text
        note.summary = summarize(note)
        notes[id] = note
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

    private func finish(actor: Actor, entries: [ChangeSet.Entry], dryRun: Bool, key: String?) -> ChangeSet {
        let cs = changeSets.make(actor: actor, entries: entries, isDryRun: dryRun, idempotencyKey: key)
        if !dryRun { idempotency.remember(cs, actor: actor) }
        return cs
    }

    private func path(of note: StoredNote) -> String {
        guard let id = note.summary.courseID, let course = courses.first(where: { $0.id == id }) else {
            return VaultPath.filename(fromTitle: note.fileTitle) + ".md"
        }
        return ServiceRules.notePath(semester: semester, course: course, fileTitle: note.fileTitle)
    }

    private func fileNameTaken(_ title: String, in course: CourseID, except id: NoteID?) -> Bool {
        let name = VaultPath.filename(fromTitle: title)
        return notes.values.contains {
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
