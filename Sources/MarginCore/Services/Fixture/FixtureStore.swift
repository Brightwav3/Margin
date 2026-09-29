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
        /// The frontmatter block as the vault sample would write it (`nil` for notes without one).
        var frontmatter: Frontmatter?
        var body: String

        /// The whole file: frontmatter followed by the body.
        var content: String { (frontmatter?.render() ?? "") + body }
    }

    /// Unsorted captures (`_inbox/`), newest last in insertion order.
    var inbox: [InboxItem]
    /// File name stem (`2026-09-28 0912 …`) of each inbox item by id.
    var inboxStems: [String: String] = [:]
    private(set) var semester: Semester
    let clock: any Clock
    var courses: [Course]
    /// Graded items of all courses (`GradeService`), in file order per course.
    var grades: [Grade]
    /// Snapshot files of `HistoryService`: note id, then file name.
    var historyFiles: [NoteID: [String: Data]] = [:]
    /// Overrides of single classes (`CourseCatalogWriter.override`), sorted by day, then id.
    var overrides: [SessionOverride] = []
    var notes: [NoteID: StoredNote] = [:] { didSet { analysisIndex = nil } }
    /// Index over the current notes for `FixtureNoteAnalysis`; dropped on every change.
    private var analysisIndex: NoteIndex?
    var changeSets: ChangeSetFactory
    var idempotency = IdempotencyCache()
    let extractor: TaskExtractor
    private let scanner = MarkdownScanner()

    nonisolated let noteChanges = Broadcaster<[NoteChange]>()
    nonisolated let catalogUpdates = Broadcaster<CatalogUpdate>()
    nonisolated let taskChanges = Broadcaster<TaskUpdate>()
    private var taskSnapshot: [NoteID: TaskSnapshotEntry] = [:]

    init(world: FixtureWorld, clock: any Clock) {
        self.semester = world.semester
        self.clock = clock
        self.courses = world.courses
        self.grades = world.grades
        self.inbox = world.inbox
        for item in world.inbox { inboxStems[item.id] = CaptureRules.inboxStem(captured: item.captured, text: item.text) }
        self.changeSets = ChangeSetFactory(clock: clock)
        self.extractor = TaskExtractor(clock: clock)
        for summary in world.allNotes {
            let body = world.markdownBody(of: summary.id) ?? "# \(summary.title)\n"
            var frontmatter: Frontmatter?
            if let course = world.courses.first(where: { $0.id == summary.courseID }) {
                frontmatter = Frontmatter.parse(SampleVaultGenerator.noteFile(summary, course: course, body: body)).frontmatter
            }
            notes[summary.id] = StoredNote(summary: summary, fileTitle: summary.title, frontmatter: frontmatter, body: body)
        }
        taskSnapshot = Self.snapshot(of: notes, extractor: extractor)
    }

    // MARK: Courses

    func semesters() -> [Semester] { [semester] }

    func courses(query: String?) -> [Course] {
        // Like the vault: an archived semester is not "the current one".
        guard !semester.isArchived else { return [] }
        return ServiceRules.sortCourses(courses.filter { ServiceRules.matches($0, query: query) })
    }

    func course(id: CourseID) throws -> Course {
        guard let c = courses.first(where: { $0.id == id }) else { throw MarginError.notFound("No course \(id)") }
        return c
    }

    func sessions(week: Int) throws -> [SessionOccurrence] {
        guard !semester.isArchived else { throw MarginError.notFound("This vault has no semester") }
        return try ServiceRules.occurrences(week: week, semester: semester, courses: courses, overrides: overrides)
    }

    /// Courses whose exams are due: none in an archived semester.
    var liveCourses: [Course] { semester.isArchived ? [] : courses }

    /// Archived semesters are read-only (spec 05 §1, `CourseCatalogWriter.setArchived`).
    func requireWritable() throws {
        if semester.isArchived { throw MarginError.readOnly("\(semester.name) is archived and read-only") }
    }

    func setSemesterArchived(_ archived: Bool) { semester.isArchived = archived }

    // MARK: Notes (read)

    func notes(course: CourseID?) throws -> [NoteSummary] {
        if let course { _ = try self.course(id: course) }
        return ServiceRules.sortNotes(notes.values.map(\.summary).filter { course == nil || $0.courseID == course })
    }

    func open(id: NoteID) throws -> Note {
        guard let n = notes[id] else { throw MarginError.notFound("No note \(id)") }
        return Note(summary: n.summary, text: n.body, version: Self.version(of: n.content))
    }

    // MARK: Tasks (read)

    private func extractTasks(of note: StoredNote) -> [TaskItem] {
        extractor.extract(from: note.body).map {
            extractor.taskItem($0, noteID: note.summary.id, courseID: note.summary.courseID)
        }
    }

    func today() -> [TaskItem] {
        ServiceRules.todayItems(tasks: allTasks(), exams: ServiceRules.examItems(liveCourses), clock: clock)
    }

    func upcoming() -> [TaskItem] {
        ServiceRules.upcomingItems(tasks: allTasks(), exams: ServiceRules.examItems(liveCourses), clock: clock)
    }

    func tasks(course id: CourseID) throws -> [TaskItem] {
        _ = try course(id: id)
        let items = notes.values.filter { $0.summary.courseID == id }.flatMap { extractTasks(of: $0) }
        return ServiceRules.courseTasks(items, today: clock.today)
    }

    private static func snapshot(of notes: [NoteID: StoredNote], extractor: TaskExtractor) -> [NoteID: TaskSnapshotEntry] {
        var result: [NoteID: TaskSnapshotEntry] = [:]
        for (id, note) in notes {
            guard let course = note.summary.courseID else { continue }
            let tasks = extractor.extract(from: note.body).map {
                extractor.taskItem($0, noteID: id, courseID: course)
            }
            result[id] = TaskSnapshotEntry(noteID: id, courseID: course, tasks: tasks)
        }
        return result
    }

    /// Publishes the difference between the tasks now and at the last call. Called after every
    /// mutation, so `TaskService.updates` follows writes and simulated outside edits alike.
    func publishTaskChanges() {
        let now = Self.snapshot(of: notes, extractor: extractor)
        let update = TaskDiff.update(old: taskSnapshot, new: now)
        taskSnapshot = now
        if let update { taskChanges.send(update) }
    }

    func allTasks() -> [TaskItem] {
        notes.values.filter { $0.summary.courseID != nil }.flatMap { extractTasks(of: $0) }
    }

    // MARK: Tasks (write)

    func toggleTask(id taskID: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                    idempotencyKey: String?) throws -> ChangeSet {
        try TaskEditing.requireTask(id: taskID)
        var found: TaskItem?
        for key in notes.keys.sorted() {
            if let note = notes[key], let task = extractTasks(of: note).first(where: { $0.id == taskID }) { found = task; break }
        }
        guard let item = found else { throw MarginError.notFound("No task \(taskID)") }
        // Same steps as `TaskWriteBack` in the vault: find the task again in the current text, flip it.
        return try editContent(id: item.source.noteID, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                               idempotencyKey: idempotencyKey) { note in
            guard let match = TaskLocator.resolve(TaskTarget(item: item), in: extractor.extract(from: note.body)) else {
                throw MarginError.notFound("Task \"\(item.text)\" is no longer in \(item.source.noteID)")
            }
            guard let body = TaskWriteBack.setting(!match.task.done, in: note.body, task: match.task) else {
                throw MarginError.invalid("Line \(match.task.line) is not a checkbox")
            }
            return (note.frontmatter?.render() ?? "") + body
        }
    }

    func setTaskDue(id taskID: String, due: LocalDate?, actor: Actor, baseVersion: String?, dryRun: Bool,
                    idempotencyKey: String?) throws -> ChangeSet {
        try TaskEditing.requireTask(id: taskID)
        var found: TaskItem?
        for key in notes.keys.sorted() {
            if let note = notes[key], let task = extractTasks(of: note).first(where: { $0.id == taskID }) { found = task; break }
        }
        guard let item = found else { throw MarginError.notFound("No task \(taskID)") }
        return try editContent(id: item.source.noteID, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                               idempotencyKey: idempotencyKey) { note in
            guard let match = TaskLocator.resolve(TaskTarget(item: item), in: extractor.extract(from: note.body)) else {
                throw MarginError.notFound("Task \"\(item.text)\" is no longer in \(item.source.noteID)")
            }
            return (note.frontmatter?.render() ?? "") + (try DueDateWriter.setting(due, in: note.body, task: match.task))
        }
    }

    // MARK: Notes (write)

    func save(id: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        try requireWritable()
        guard var note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        let current = Self.version(of: note.content)
        try requireBaseVersion(baseVersion, matches: current, what: "Note \(id)")
        var entries: [ChangeSet.Entry] = []
        if text != note.body {
            note.body = text
            entries = [.init(path: path(of: note), kind: .modified, noteID: id, beforeHash: current,
                             afterHash: Self.version(of: note.content))]
            note.summary = summarize(note)
            if !dryRun { notes[id] = note }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    /// Rewrites the whole file content of a note (frontmatter + body) through `transform`, which
    /// returns `nil` for "nothing to change". Shared by the property and task write paths.
    func editContent(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?,
                     transform: (StoredNote) throws -> String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        try requireWritable()
        guard var note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        let current = Self.version(of: note.content)
        try requireBaseVersion(baseVersion, matches: current, what: "Note \(id)")
        var entries: [ChangeSet.Entry] = []
        if let newContent = try transform(note), newContent != note.content {
            let parsed = Frontmatter.parse(newContent)
            note.frontmatter = parsed.frontmatter
            note.body = parsed.body
            entries = [.init(path: path(of: note), kind: .modified, noteID: id, beforeHash: current,
                             afterHash: Self.version(of: note.content))]
            note.summary = summarize(note)
            if !dryRun { notes[id] = note }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    // MARK: Analysis

    /// A `NoteIndex` over the current notes, built on first use after a change. The fixture answers
    /// analysis queries from the same index code as the vault, so both agree by construction.
    func noteIndex() async -> NoteIndex {
        if let analysisIndex { return analysisIndex }
        let index = NoteIndex(clock: clock)
        await index.build(entries: notes.keys.sorted().compactMap { id in
            notes[id].map { (path: path(of: $0), content: $0.content) }
        })
        // Another call may have built one (or a write invalidated the notes) while this one awaited.
        if let analysisIndex { return analysisIndex }
        analysisIndex = index
        return index
    }

    // MARK: Properties

    private func propertyRegistry() -> PropertyRegistry {
        PropertyEditing.registry(inferredFrom: notes.keys.sorted().compactMap { id in
            notes[id]?.frontmatter.map { fm in Dictionary(uniqueKeysWithValues: fm.keys.compactMap { k in fm.value(for: k).map { (k, $0) } }) }
        })
    }

    func propertyTypes() -> [String: PropertyType] { propertyRegistry().types }

    func setProperty(key: String, value: FrontmatterValue, on id: NoteID, actor: Actor, baseVersion: String?,
                     dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        let registry = propertyRegistry()
        return try editContent(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey) {
            try PropertyEditing.set(key: key, value: value, in: $0.content, registry: registry)
        }
    }

    func removeProperty(key: String, on id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool,
                        idempotencyKey: String?) throws -> ChangeSet {
        try editContent(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun, idempotencyKey: idempotencyKey) {
            try PropertyEditing.remove(key: key, in: $0.content)
        }
    }

    func create(course courseID: CourseID, title: String, kind: NoteKind, text: String, actor: Actor,
                dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let course = try self.course(id: courseID)
        try requireWritable()
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw MarginError.invalid("A note needs a title") }
        let id = ServiceRules.noteID(course: courseID, title: title)
        guard notes[id] == nil, !fileNameTaken(title, in: courseID, except: nil) else {
            throw MarginError.conflict("A note named \(title) already exists in \(course.name)")
        }
        var note = StoredNote(
            summary: NoteSummary(id: id, courseID: courseID, title: title, kind: kind),
            fileTitle: title, frontmatter: Self.newFrontmatter(id: id, course: course, kind: kind),
            body: ServiceRules.initialBody(title: title, text: text))
        note.summary = summarize(note)
        let entry = ChangeSet.Entry(path: path(of: note), kind: .created, noteID: id, afterHash: Self.version(of: note.content))
        if !dryRun { notes[id] = note }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }

    func move(id: NoteID, toCourse target: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        try requireWritable()
        guard var note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        _ = try course(id: target)
        let version = Self.version(of: note.content)
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
        try requireWritable()
        guard let note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        let version = Self.version(of: note.content)
        try requireBaseVersion(baseVersion, matches: version, what: "Note \(id)")
        let entry = ChangeSet.Entry(path: path(of: note), kind: .deleted, noteID: id, beforeHash: version)
        if !dryRun { notes[id] = nil }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }

    /// The whole file content of a note (frontmatter + body), as the vault would store it.
    func rawContent(id: NoteID) throws -> String {
        guard let n = notes[id] else { throw MarginError.notFound("No note \(id)") }
        return n.content
    }

    // MARK: Simulated outside changes (tests, previews)

    /// Replaces a note's body as if another program had edited the file.
    func simulateExternalEdit(id: NoteID, text: String) throws {
        guard var note = notes[id] else { throw MarginError.notFound("No note \(id)") }
        note.body = text
        note.summary = summarize(note)
        notes[id] = note
        publishTaskChanges()
        noteChanges.send([NoteChange(noteID: id, kind: .modified)])
    }

    func simulateExternalCreate(course: CourseID, title: String, text: String) throws -> NoteID {
        _ = try self.course(id: course)
        let id = ServiceRules.noteID(course: course, title: title)
        let owner = try self.course(id: course)
        var note = StoredNote(summary: NoteSummary(id: id, courseID: course, title: title), fileTitle: title,
                              frontmatter: Self.newFrontmatter(id: id, course: owner, kind: .note), body: ServiceRules.initialBody(title: title, text: text))
        note.summary = summarize(note)
        notes[id] = note
        publishTaskChanges()
        noteChanges.send([NoteChange(noteID: id, kind: .created)])
        return id
    }

    func simulateExternalDelete(id: NoteID) throws {
        guard notes[id] != nil else { throw MarginError.notFound("No note \(id)") }
        notes[id] = nil
        publishTaskChanges()
        noteChanges.send([NoteChange(noteID: id, kind: .deleted)])
    }

    /// Changes a course as if `_course.md` had been edited elsewhere.
    func simulateExternalCourseEdit(id: CourseID, _ change: @Sendable (inout Course) -> Void) throws {
        guard let i = courses.firstIndex(where: { $0.id == id }) else { throw MarginError.notFound("No course \(id)") }
        let examsBefore = courses[i].exams
        change(&courses[i])
        if courses[i].exams != examsBefore { taskChanges.send(TaskUpdate(noteIDs: [], courseIDs: [id])) }
        catalogUpdates.send(CatalogUpdate(courses: [id]))
    }

    // MARK: Helpers

    /// The frontmatter a note created through the app gets (same keys as `VaultNoteRepository.create`).
    static func newFrontmatter(id: NoteID, course: Course, kind: NoteKind) -> Frontmatter? {
        let text = "---\nid: \(SampleVaultGenerator.scalar(id))\nclass: \"[[\(course.name)]]\"\ntype: \(kind.rawValue)\n---\n"
        return Frontmatter.parse(text).frontmatter
    }

    static func version(of body: String) -> String { ContentHash(of: body).hex }

    func finish(actor: Actor, entries: [ChangeSet.Entry], dryRun: Bool, key: String?) -> ChangeSet {
        publishTaskChanges()
        let cs = changeSets.make(actor: actor, entries: entries, isDryRun: dryRun, idempotencyKey: key)
        if !dryRun { idempotency.remember(cs, actor: actor) }
        return cs
    }

    func path(of note: StoredNote) -> String {
        guard let id = note.summary.courseID, let course = courses.first(where: { $0.id == id }) else {
            return VaultPath.filename(fromTitle: note.fileTitle) + ".md"
        }
        return ServiceRules.notePath(semester: semester, course: course, fileTitle: note.fileTitle)
    }

    func fileNameTaken(_ title: String, in course: CourseID, except id: NoteID?) -> Bool {
        let name = VaultPath.filename(fromTitle: title)
        return notes.values.contains {
            $0.summary.courseID == course && $0.summary.id != id && VaultPath.filename(fromTitle: $0.fileTitle) == name
        }
    }

    /// Recomputes what the index would derive from the body.
    func summarize(_ note: StoredNote) -> NoteSummary {
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
