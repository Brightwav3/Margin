import Foundation

/// The state shared by the `Vault…` services: the store, the index, the course model and the file
/// watcher that keeps them current. One instance per open vault.
///
/// Reads go through the index (kept fresh by the watcher and by the app's own writes); writes go
/// through `VaultStore` (atomic, `expectedVersion`) and update the index right away, since the
/// watcher does not report the app's own writes.
actor VaultBackend {
    let store: VaultStore
    let index: NoteIndex
    let clock: any Clock
    /// Progress of the index build (`IndexStatus`).
    nonisolated let indexProgress: IndexProgressTracker

    nonisolated let noteChanges = Broadcaster<[NoteChange]>()
    nonisolated let catalogUpdates = Broadcaster<CatalogUpdate>()
    /// Tasks of the vault with change tracking; its `updates` feed `TaskService.updates`.
    let tasksStore: TasksStore
    /// Writes task checkboxes to note files (used by `TaskService.toggle`).
    let taskWriteBack: TaskWriteBack

    private(set) var model = VaultCourseModel()
    var changeSets: ChangeSetFactory
    var idempotency = IdempotencyCache()
    let rewriter = WikilinkRewriter()
    private var watchTask: Task<Void, Never>?

    private init(store: VaultStore, index: NoteIndex, clock: any Clock, indexProgress: IndexProgressTracker) {
        self.store = store; self.index = index; self.clock = clock; self.indexProgress = indexProgress
        self.tasksStore = TasksStore(index: index)
        self.taskWriteBack = TaskWriteBack(store: store, index: index, clock: clock)
        self.changeSets = ChangeSetFactory(clock: clock)
    }

    /// Opens the vault, builds the index and starts watching.
    ///
    /// - Parameter watchInterval: seconds between scans of the portable watcher.
    /// - Parameter onProgress: called while the index is built (`IndexProgress`, whole-percent steps,
    ///   the last one complete), from whatever thread the build runs on.
    static func open(at url: URL, clock: any Clock, watchInterval: TimeInterval = 0.3,
                     onProgress: (@Sendable (IndexProgress) -> Void)? = nil) async throws -> VaultBackend {
        // A generous TTL: on a busy machine the poller may lag far behind the app's own writes.
        let ownWrites = OwnWriteRegistry(ttl: 60)
        let store = try await VaultStore.open(root: url, clock: clock, ownWrites: ownWrites)
        let index = NoteIndex(clock: clock)
        let tracker = IndexProgressTracker(observer: onProgress)
        try await index.build(from: VaultNoteSource(store: store)) { done, total in
            tracker.report(done: done, total: total)
        }
        tracker.finish()
        let backend = VaultBackend(store: store, index: index, clock: clock, indexProgress: tracker)
        await store.addRenameObserver(backend.rewriter)
        await backend.reloadModel()
        await backend.primeTasks()
        // The watcher compares file times, which are real time, so it always uses the system clock.
        let watcher = PollingFileWatcher(root: store.root, interval: watchInterval, ownWrites: ownWrites)
        await backend.startWatching(watcher)
        return backend
    }

    /// Stops watching and ends all update streams.
    func shutdown() {
        watchTask?.cancel()
        watchTask = nil
        noteChanges.finishAll()
        catalogUpdates.finishAll()
        tasksStore.updates.finishAll()
        indexProgress.finishAll()
    }

    // MARK: Watching

    private func startWatching(_ watcher: any FileWatcher) {
        let changes = watcher.changes()   // the baseline is taken here, before any later change
        watchTask = Task { [weak self] in
            for await batch in changes {
                guard let self else { return }
                await self.handle(batch)
            }
        }
    }

    private func handle(_ batch: [FileChange]) async {
        var idsBefore: [String: NoteID] = [:]
        for change in batch { if let r = await index.note(byPath: change.path) { idsBefore[change.path] = r.id } }
        await index.apply(batch)

        var notes: [NoteChange] = []
        for change in batch where Self.isNotePath(change.path) {
            switch change.kind {
            case .deleted:
                if let id = idsBefore[change.path] { notes.append(NoteChange(noteID: id, kind: .deleted)) }
            case .created, .modified:
                if let id = await index.note(byPath: change.path)?.id {
                    notes.append(NoteChange(noteID: id, kind: change.kind == .created && idsBefore[change.path] == nil ? .created : .modified))
                }
            }
        }
        if batch.contains(where: { $0.path.split(separator: "/").last == "_course.md" }) {
            let old = model.entries
            await reloadModel()
            let changed = Self.changedCourses(old: old, new: model.entries)
            if !changed.isEmpty { catalogUpdates.send(CatalogUpdate(courses: changed)) }
            // A course file can change which course a note belongs to, and the exam dates.
            await tasksMayHaveChanged(paths: nil)
            await tasksStore.publish(courses: Self.coursesWithChangedExams(old: old.map(\.course), new: model.courses))
        } else {
            await tasksMayHaveChanged(paths: batch.map(\.path))
        }
        if !notes.isEmpty { noteChanges.send(notes.sorted { ($0.noteID, $0.kind.rawValue) < ($1.noteID, $1.kind.rawValue) }) }
    }

    static func coursesWithChangedExams(old: [Course], new: [Course]) -> [CourseID] {
        let before = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0.exams) })
        let after = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0.exams) })
        return Set(before.keys).union(after.keys).filter { (before[$0] ?? []) != (after[$0] ?? []) }.sorted()
    }

    /// Courses whose file changed in a way the catalog shows: the course itself or its overrides.
    static func changedCourses(old: [VaultCourseModel.Entry], new: [VaultCourseModel.Entry]) -> [CourseID] {
        let before = Dictionary(uniqueKeysWithValues: old.map { ($0.course.id, [$0.course] as [Course] + []) })
        let after = Dictionary(uniqueKeysWithValues: new.map { ($0.course.id, [$0.course] as [Course] + []) })
        let overridesBefore = Dictionary(uniqueKeysWithValues: old.map { ($0.course.id, $0.overrides) })
        let overridesAfter = Dictionary(uniqueKeysWithValues: new.map { ($0.course.id, $0.overrides) })
        return Set(before.keys).union(after.keys).filter {
            before[$0] != after[$0] || overridesBefore[$0] != overridesAfter[$0]
        }.sorted()
    }

    func reloadModel() async {
        model = await VaultCourseModel.load(from: store, clock: clock)
    }

    // MARK: What is a note

    /// Markdown files that are notes: not `_course.md`/`_grades.md` (underscore names), not below a
    /// `_`-folder (`_inbox`, `_archive`), not hidden.
    static func isNotePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard let first = parts.first, let last = parts.last, path.lowercased().hasSuffix(".md") else { return false }
        return !first.hasPrefix("_") && !first.hasPrefix(".") && !last.hasPrefix("_")
    }

    func courseID(of record: NoteRecord) -> CourseID? {
        if let archived = archivedEntry(forNotePath: record.path) { return archived.course.id }
        return model.courseID(semesterFolder: record.semesterID, folder: record.courseID, className: record.className)
    }

    private func summary(of record: NoteRecord) -> NoteSummary {
        var s = record.summary
        s.courseID = courseID(of: record)
        return s
    }

    private func noteRecords() async -> [NoteRecord] {
        await index.allNotes.filter { Self.isNotePath($0.path) }
    }

    private func record(_ id: NoteID) async throws -> NoteRecord {
        guard let r = await index.note(byID: id), Self.isNotePath(r.path) || Self.isArchivedNotePath(r.path) else {
            throw MarginError.notFound("No note \(id)")
        }
        return r
    }

    // MARK: Courses

    func semesters() -> [Semester] { model.semesters }

    /// Courses that can be written: not in an archived semester (their exams are not "due" either).
    var liveCourses: [Course] {
        let archived = Set(model.semesters.filter(\.isArchived).map(\.id))
        return model.entries.filter { !$0.archived && !archived.contains($0.course.semester) }.map(\.course)
    }

    /// The semester that is "now": archived ones never are.
    func currentSemester() -> Semester? {
        ServiceRules.currentSemester(model.semesters.filter { !$0.isArchived }, today: clock.today)
    }

    func courses(query: String?) -> [Course] {
        guard let current = currentSemester() else { return [] }
        return ServiceRules.sortCourses(model.courses.filter { $0.semester == current.id && ServiceRules.matches($0, query: query) })
    }

    func course(id: CourseID) throws -> Course {
        guard let e = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        return e.course
    }

    func sessions(week: Int) throws -> [SessionOccurrence] {
        guard let current = currentSemester() else { throw MarginError.notFound("This vault has no semester") }
        return try ServiceRules.occurrences(week: week, semester: current, courses: model.courses.filter { $0.semester == current.id },
                                            overrides: overrides(in: current))
    }

    // MARK: Notes (read)

    func notes(course: CourseID?) async throws -> [NoteSummary] {
        if let course, model.entry(course)?.archived == true {
            // A course of an archived semester: its notes are readable, and only listed by course.
            let records = await index.allNotes.filter { Self.isArchivedNotePath($0.path) && archivedEntry(forNotePath: $0.path)?.course.id == course }
            return ServiceRules.sortNotes(records.map { summary(of: $0) })
        }
        if let course { _ = try self.course(id: course) }
        let all = await noteRecords().map { summary(of: $0) }
        return ServiceRules.sortNotes(all.filter { course == nil || $0.courseID == course })
    }

    func open(id: NoteID) async throws -> Note {
        let r = try await record(id)
        let (content, version) = try await store.read(VaultPath(r.path))
        // Reading is the moment the index catches up with what is on disk.
        if await index.update(path: r.path, content: content) { await tasksMayHaveChanged(paths: [r.path]) }
        let fresh = await index.note(byPath: r.path) ?? r
        return Note(summary: summary(of: fresh), text: Frontmatter.parse(content).body, version: version.hex)
    }

    // MARK: Tasks (read)

    private var courseResolver: TasksStore.CourseResolver {
        let model = self.model
        return { model.courseID(semesterFolder: $0.semesterID, folder: $0.courseID, className: $0.className) }
    }

    private func allTasks(course: CourseID? = nil) async -> [TaskItem] {
        await tasksStore.allTasks(courseOf: courseResolver, course: course)
    }

    func primeTasks() async { await tasksStore.prime(courseOf: courseResolver) }

    /// Tells the tasks store that the tasks of these notes may have changed (`nil`: any note), so
    /// `TaskService.updates` reports the difference. Called after every write and every watcher batch.
    func tasksMayHaveChanged(paths: [String]?) async {
        await tasksStore.reconcile(paths: paths, courseOf: courseResolver)
    }

    func today() async -> [TaskItem] {
        ServiceRules.todayItems(tasks: await allTasks(), exams: ServiceRules.examItems(liveCourses), clock: clock)
    }

    func upcoming() async -> [TaskItem] {
        ServiceRules.upcomingItems(tasks: await allTasks(), exams: ServiceRules.examItems(liveCourses), clock: clock)
    }

    func tasks(course id: CourseID) async throws -> [TaskItem] {
        _ = try course(id: id)
        return ServiceRules.courseTasks(await allTasks(course: id), today: clock.today)
    }

    // MARK: Notes (write)

    func save(id: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let r = try await record(id)
        try requireWritable(path: r.path)
        let path = try VaultPath(r.path)
        let (content, version) = try await store.read(path)
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Note \(id)")
        let (fm, _) = Frontmatter.parse(content)
        let newContent = (fm?.render() ?? "") + text
        var entries: [ChangeSet.Entry] = []
        if newContent != content {
            entries = [.init(path: r.path, kind: .modified, noteID: id, beforeHash: version.hex,
                             afterHash: ContentHash(of: newContent).hex)]
            if !dryRun {
                try await store.write(path, content: newContent, expectedVersion: version)
                await index.update(path: r.path, content: newContent)
                await tasksMayHaveChanged(paths: [r.path])
            }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func create(course courseID: CourseID, title: String, kind: NoteKind, text: String, actor: Actor,
                dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let entry = model.entry(courseID) else { throw MarginError.notFound("No course \(courseID)") }
        try requireWritable(course: entry)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw MarginError.invalid("A note needs a title") }
        let id = ServiceRules.noteID(course: courseID, title: title)
        guard await index.note(byID: id) == nil else {
            throw MarginError.conflict("A note with id \(id) already exists")
        }
        let path = try VaultPath(components: [entry.semesterFolder, entry.folder, VaultPath.filename(fromTitle: title) + ".md"])
        if await store.exists(path) { throw MarginError.conflict("\(path) already exists") }
        let content = """
            ---
            id: \(SampleVaultGenerator.scalar(id))
            class: "[[\(entry.course.name)]]"
            type: \(kind.rawValue)
            ---

            """ + ServiceRules.initialBody(title: title, text: text)
        let change = ChangeSet.Entry(path: path.rawValue, kind: .created, noteID: id, afterHash: ContentHash(of: content).hex)
        if !dryRun {
            try await store.create(path, content: content)
            await index.update(path: path.rawValue, content: content)
            await tasksMayHaveChanged(paths: [path.rawValue])
        }
        return finish(actor: actor, entries: [change], dryRun: dryRun, key: idempotencyKey)
    }

    func move(id: NoteID, toCourse target: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let r = try await record(id)
        try requireWritable(path: r.path)
        guard let entry = model.entry(target) else { throw MarginError.notFound("No course \(target)") }
        try requireWritable(course: entry)
        let from = try VaultPath(r.path)
        let version = try await store.read(from).version
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Note \(id)")
        let to = try VaultPath(components: [entry.semesterFolder, entry.folder, from.lastComponent])
        var entries: [ChangeSet.Entry] = []
        if from != to {
            if await store.exists(to) { throw MarginError.conflict("\(to) already exists") }
            entries = [.init(path: to.rawValue, kind: .moved, noteID: id, fromPath: from.rawValue,
                             beforeHash: version.hex, afterHash: version.hex)]
            if !dryRun {
                try await store.rename(from, to: to)
                await index.rename(from: from.rawValue, to: to.rawValue)
                // The rename observer rewrote links in other notes; bring the index up to date.
                var touched = [from.rawValue, to.rawValue]
                for rewritten in await rewriter.lastReport.notesRewritten {
                    _ = try? await index.update(path: rewritten.rawValue)
                    touched.append(rewritten.rawValue)
                }
                await tasksMayHaveChanged(paths: touched)
            }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func delete(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let r = try await record(id)
        try requireWritable(path: r.path)
        let path = try VaultPath(r.path)
        let version = try await store.read(path).version
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Note \(id)")
        let entry = ChangeSet.Entry(path: r.path, kind: .deleted, noteID: id, beforeHash: version.hex)
        if !dryRun {
            try await store.trash(path)
            await index.remove(path: r.path)
            await tasksMayHaveChanged(paths: [r.path])
        }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }

    /// Rewrites a note file through `transform` (whole content in, new content or `nil` out) with the
    /// usual write rules. Shared by the property and task write paths.
    func editContent(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?,
                     transform: (_ content: String, _ record: NoteRecord) throws -> String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let r = try await record(id)
        try requireWritable(path: r.path)
        let path = try VaultPath(r.path)
        let (content, version) = try await store.read(path)
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Note \(id)")
        var entries: [ChangeSet.Entry] = []
        if let newContent = try transform(content, r), newContent != content {
            entries = [.init(path: r.path, kind: .modified, noteID: id, beforeHash: version.hex,
                             afterHash: ContentHash(of: newContent).hex)]
            if !dryRun {
                try await store.write(path, content: newContent, expectedVersion: version)
                if await index.update(path: r.path, content: newContent) { await tasksMayHaveChanged(paths: [r.path]) }
            }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    // MARK: Tasks (write)

    /// Flips a task through `TaskWriteBack` (finds it again in the current file text, retries when the
    /// file changes meanwhile) and lets the tasks store know, so `TaskService.updates` fires.
    func toggleTask(id taskID: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                    idempotencyKey: String?) async throws -> ChangeSet {
        try TaskEditing.requireTask(id: taskID)
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        var found: TaskItem?
        for record in await noteRecords() {
            if let task = record.tasks.first(where: { $0.id == taskID }) { found = task; break }
        }
        guard let item = found else { throw MarginError.notFound("No task \(taskID)") }
        let result = try await taskWriteBack.setDone(!item.done, task: item, baseVersion: baseVersion, dryRun: dryRun)
        if !dryRun, result.entry != nil { await tasksMayHaveChanged(paths: [result.path]) }
        return finish(actor: actor, entries: result.entry.map { [$0] } ?? [], dryRun: dryRun, key: idempotencyKey)
    }

    /// Sets or removes a task's due date through `TaskWriteBack` (same steps as `toggleTask`).
    func setTaskDue(id taskID: String, due: LocalDate?, actor: Actor, baseVersion: String?, dryRun: Bool,
                    idempotencyKey: String?) async throws -> ChangeSet {
        try TaskEditing.requireTask(id: taskID)
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        var found: TaskItem?
        for record in await noteRecords() {
            if let task = record.tasks.first(where: { $0.id == taskID }) { found = task; break }
        }
        guard let item = found else { throw MarginError.notFound("No task \(taskID)") }
        let result = try await taskWriteBack.setDue(due, task: item, baseVersion: baseVersion, dryRun: dryRun)
        if !dryRun, result.entry != nil { await tasksMayHaveChanged(paths: [result.path]) }
        return finish(actor: actor, entries: result.entry.map { [$0] } ?? [], dryRun: dryRun, key: idempotencyKey)
    }

    // MARK: Properties

    func propertyRegistry() async -> PropertyRegistry {
        PropertyEditing.registry(inferredFrom: await noteRecords().map(\.properties))
    }

    func propertyTypes() async -> [String: PropertyType] { await propertyRegistry().types }

    func setProperty(key: String, value: FrontmatterValue, on id: NoteID, actor: Actor, baseVersion: String?,
                     dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        let registry = await propertyRegistry()
        return try await editContent(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                     idempotencyKey: idempotencyKey) { content, _ in
            try PropertyEditing.set(key: key, value: value, in: content, registry: registry)
        }
    }

    func removeProperty(key: String, on id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool,
                        idempotencyKey: String?) async throws -> ChangeSet {
        try await editContent(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                              idempotencyKey: idempotencyKey) { content, _ in
            try PropertyEditing.remove(key: key, in: content)
        }
    }

    func finish(actor: Actor, entries: [ChangeSet.Entry], dryRun: Bool, key: String?) -> ChangeSet {
        let cs = changeSets.make(actor: actor, entries: entries, isDryRun: dryRun, idempotencyKey: key)
        if !dryRun { idempotency.remember(cs, actor: actor) }
        return cs
    }
}
