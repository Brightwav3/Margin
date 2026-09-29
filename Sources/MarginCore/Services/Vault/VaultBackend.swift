import Foundation

/// The state shared by the `Vault…` services: the store, the index, the course model and the file
/// watcher that keeps them current. One instance per open vault.
///
/// Reads go through the index (kept fresh by the watcher and by the app's own writes); writes go
/// through `VaultStore` (atomic, `expectedVersion`) inside a `ChangeSetJournal` transaction (so
/// every write is one all-or-nothing, undoable group) and update the index right away, since the
/// watcher does not report the app's own writes.
///
/// Writes run one at a time (`writeGate`), so two callers in this process never interleave their
/// read-check-write steps; writers outside the process are caught by the store's `expectedVersion`
/// check and the write is retried against what they wrote.
actor VaultBackend {
    private nonisolated let dedicatedExecutor = DedicatedExecutor(label: "margin.vault-backend")
    nonisolated var unownedExecutor: UnownedSerialExecutor { dedicatedExecutor.asUnownedSerialExecutor() }
    let store: VaultStore
    let index: NoteIndex
    let clock: any Clock
    let journal: ChangeSetJournal
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
    private var versions = TextVersionCache()
    /// Held for the whole of every write: the writes of this process run one at a time.
    let writeGate = AsyncMutex()
    let rewriter = WikilinkRewriter()
    private var watchTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    /// Notes the index could not read (permission denied, I/O error). Making a file readable again
    /// does not change its modification time, so the watcher never mentions it: these are read
    /// again on a timer until they can be, then indexed like any new note.
    private var unreadable: Set<String> = []

    /// How often a write is retried against a newer stored version when another program changes
    /// the file between the read and the write.
    private static let maxWriteAttempts = 6

    private init(store: VaultStore, index: NoteIndex, clock: any Clock, journal: ChangeSetJournal,
                 indexProgress: IndexProgressTracker) {
        self.store = store; self.index = index; self.clock = clock; self.journal = journal
        self.indexProgress = indexProgress
        self.tasksStore = TasksStore(index: index)
        self.taskWriteBack = TaskWriteBack(store: store, index: index, clock: clock)
        self.changeSets = ChangeSetFactory(clock: clock)
    }

    /// Opens the vault, builds the index and starts watching.
    ///
    /// Transactions a previous run left unfinished are rolled back first (see `ChangeSetJournal`).
    ///
    /// - Parameters:
    ///   - watchInterval: seconds between scans of the portable watcher.
    ///   - retention: how long and how many change sets are kept for undo.
    ///   - fileSystem: the file system the store uses (tests inject faults here).
    ///   - onProgress: called while the index is built (`IndexProgress`, whole-percent steps, the last
    ///     one complete), from whatever thread the build runs on.
    static func open(at url: URL, clock: any Clock, watchInterval: TimeInterval = 0.3,
                     retention: ChangeSetRetention = .standard,
                     fileSystem: any FileSystem = POSIXFileSystem(),
                     onProgress: (@Sendable (IndexProgress) -> Void)? = nil) async throws -> VaultBackend {
        // A generous TTL: on a busy machine the poller may lag far behind the app's own writes.
        let ownWrites = OwnWriteRegistry(ttl: 60)
        let store = try await VaultStore.open(root: url, fileSystem: fileSystem, clock: clock, ownWrites: ownWrites)
        let journal = try await ChangeSetJournal.open(store: store, clock: clock, retention: retention)
        let index = NoteIndex(clock: clock)
        let tracker = IndexProgressTracker(observer: onProgress)
        let unreadable = try await index.build(from: VaultNoteSource(store: store)) { done, total in
            tracker.report(done: done, total: total)
        }
        tracker.finish()
        let backend = VaultBackend(store: store, index: index, clock: clock, journal: journal, indexProgress: tracker)
        await backend.track(failures: unreadable, succeeded: [])
        await store.addRenameObserver(backend.rewriter)
        await backend.reloadModel()
        await backend.primeTasks()
        // The watcher compares file times, which are real time, so it always uses the system clock.
        #if os(macOS)
        let watcher: any FileWatcher = FSEventsFileWatcher(root: store.root, ownWrites: ownWrites)
        #else
        let watcher: any FileWatcher = PollingFileWatcher(root: store.root, interval: watchInterval, ownWrites: ownWrites)
        #endif
        await backend.startWatching(watcher, retryEvery: max(watchInterval * 5, 0.1))
        return backend
    }

    /// Stops watching and ends all update streams.
    func shutdown() {
        watchTask?.cancel()
        watchTask = nil
        retryTask?.cancel()
        retryTask = nil
        noteChanges.finishAll()
        catalogUpdates.finishAll()
        tasksStore.updates.finishAll()
        indexProgress.finishAll()
    }

    // MARK: Watching

    private func startWatching(_ watcher: any FileWatcher, retryEvery: TimeInterval) {
        let changes = watcher.changes()   // the baseline is taken here, before any later change
        watchTask = Task { [weak self] in
            for await batch in changes {
                guard let self else { return }
                await self.handle(batch)
            }
        }
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(retryEvery * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.retryUnreadable()
            }
        }
    }

    /// Remembers which notes could not be read (only failures a later read may cure) and forgets
    /// the ones that could.
    private func track(failures: [String: MarginError], succeeded: [String]) {
        for path in succeeded { unreadable.remove(path) }
        for (path, error) in failures {
            if error.code == "io" { unreadable.insert(path) } else { unreadable.remove(path) }
        }
    }

    private func retryUnreadable() async {
        for path in unreadable.sorted() {
            let idsBefore = await index.note(byPath: path).map { [path: $0.id] } ?? [:]
            do {
                let changed = try await index.update(path: path)
                unreadable.remove(path)
                if changed { await announce([FileChange(path: path, kind: .created)], idsBefore: idsBefore) }
            } catch let error as MarginError {
                if error.code != "io" { unreadable.remove(path) }
            } catch { continue }
        }
    }

    private func handle(_ batch: [FileChange]) async {
        var idsBefore: [String: NoteID] = [:]
        for change in batch { if let r = await index.note(byPath: change.path) { idsBefore[change.path] = r.id } }
        let failures = await index.apply(batch)
        track(failures: failures, succeeded: batch.map(\.path).filter { failures[$0] == nil })
        await announce(batch, idsBefore: idsBefore)
    }

    /// Follow-up of changes the index has taken in: course model, tasks and the update streams.
    private func announce(_ batch: [FileChange], idsBefore: [String: NoteID]) async {
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
        versions.remember(content, version: version.hex)
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

    /// Applies the operations a committed transaction performed to the index, the version cache, the
    /// course model and the tasks store.
    private func afterCommit(_ committed: ChangeSetJournal.Committed) async {
        var touched: [String] = []
        var courseFiles = false
        for op in committed.operations {
            touched.append(op.path)
            if let from = op.fromPath { touched.append(from) }
            if Self.isCourseFile(op.path) || (op.fromPath.map(Self.isCourseFile) ?? false) { courseFiles = true }
            switch op.kind {
            case .write, .create:
                if let before = op.before, let hash = op.beforeHash, let text = String(validating: before, as: UTF8.self) {
                    versions.remember(text, version: hash)
                }
                if let after = op.after, let text = String(validating: after, as: UTF8.self) {
                    if let hash = op.afterHash { versions.remember(text, version: hash) }
                    await index.update(path: op.path, content: text)
                } else {
                    _ = try? await index.update(path: op.path)
                }
            case .move:
                guard let from = op.fromPath else { break }
                if op.path.lowercased().hasSuffix(".md") {
                    await index.rename(from: from, to: op.path)
                    // Another program may have changed the file between the read and the move; the move
                    // carried the new bytes along, and the watcher does not report a move of our own.
                    _ = try? await index.update(path: op.path)
                } else {
                    // A folder: every note below it follows.
                    courseFiles = true
                    await renameFolderInIndex(from: from, to: op.path)
                }
            case .trash:
                await index.remove(path: op.path)
            }
        }
        if courseFiles { await courseFilesChanged() }
        if !touched.isEmpty { await tasksMayHaveChanged(paths: courseFiles ? nil : touched) }
    }

    /// `_course.md` or the semester list: files the course model is built from.
    private static func isCourseFile(_ path: String) -> Bool {
        path.split(separator: "/").last == "_course.md" || path == SemesterArchiver.semestersFile
    }

    private func renameFolderInIndex(from: String, to: String) async {
        let prefix = from + "/"
        for record in await index.allNotes where record.path.hasPrefix(prefix) {
            await index.rename(from: record.path, to: to + "/" + record.path.dropFirst(prefix.count))
        }
    }

    /// After a transaction failed and was rolled back: the files are as they were, but the code that
    /// ran inside it may already have updated the index and the course model. Read them again.
    private func reconcileAfterFailure(_ operations: [RecordedOperation]) async {
        guard !operations.isEmpty else { return }
        var folderMoved = false
        var courseFiles = false
        var paths: [String] = []
        for op in operations {
            paths.append(op.path)
            if let from = op.fromPath { paths.append(from) }
            if op.kind == .move, !op.path.lowercased().hasSuffix(".md") { folderMoved = true }
            if Self.isCourseFile(op.path) || (op.fromPath.map(Self.isCourseFile) ?? false) { courseFiles = true }
        }
        if folderMoved {
            do { try await index.build(from: VaultNoteSource(store: store)) } catch { /* the files are the truth; the next read catches up */ }
        } else {
            for path in paths where path.lowercased().hasSuffix(".md") { _ = try? await index.update(path: path) }
        }
        if courseFiles || folderMoved { await courseFilesChanged() }
        await tasksMayHaveChanged(paths: folderMoved || courseFiles ? nil : paths)
    }

    /// Identifies the note at a vault path, for change-set entries of files a write touched
    /// indirectly (notes whose links a move rewrote).
    private func noteID(atPath path: String) async -> NoteID? { await index.note(byPath: path)?.id }

    /// Runs `body` as one recorded transaction and applies its result to the index. A transaction
    /// that performed no operation (nothing to write) is not recorded.
    func runTransaction(actor: Actor, key: String?, describeAllFiles: Bool = true,
                        body: @Sendable () async throws -> [ChangeSet.Entry]) async throws -> ChangeSet {
        let committed: ChangeSetJournal.Committed
        do {
            committed = try await journal.transaction(
                actor: actor, idempotencyKey: key, noteID: { [weak self] in await self?.noteID(atPath: $0) },
                describeAllFiles: describeAllFiles, body: body)
        } catch {
            await reconcileAfterFailure(await journal.takeFailedOperations())
            throw error
        }
        guard !committed.operations.isEmpty else {
            return finish(actor: actor, entries: committed.changeSet.entries, dryRun: false, key: key)
        }
        await afterCommit(committed)
        idempotency.remember(committed.changeSet, actor: actor)
        return committed.changeSet
    }

    /// Runs a write that does its own store calls, index and model follow-ups and returns its
    /// `ChangeSet` (the capture, inbox and course writes) as one recorded, undoable group: the file
    /// operations it makes join the transaction, and the result is the recorded `ChangeSet`.
    func journaled(actor: Actor, key: String?, dryRun: Bool,
                   _ body: @escaping @Sendable () async throws -> ChangeSet) async throws -> ChangeSet {
        if dryRun { return try await body() }
        return try await writeGate.withLock {
            if let cached = idempotency.lookup(actor: actor, key: key) { return cached }
            // The write's own `ChangeSet` shape is part of its contract: keep its entries as they are.
            return try await self.runTransaction(actor: actor, key: key, describeAllFiles: false) { try await body().entries }
        }
    }

    func save(id: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet {
        try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            var attempt = 0
            while true {
                attempt += 1
                let r = try await record(id)
                try requireWritable(path: r.path)
                let path = try VaultPath(r.path)
                let (content, version) = try await store.read(path)
                versions.remember(content, version: version.hex)
                let (fm, currentBody) = Frontmatter.parse(content)

                var newBody = text
                var merged = false
                if let base = baseVersion, base != version.hex {
                    // Stale base: merge when the two sides changed different lines, else conflict.
                    guard let baseContent = versions.lookup(base) else {
                        throw MarginError.conflict(
                            "Note \(id) changed since version \(base.prefix(12)) (now \(version.hex.prefix(12)))",
                            ConflictDetail(path: r.path, currentVersion: version.hex))
                    }
                    let result = ThreeWayMerge.merge(base: Frontmatter.parse(baseContent).body, ours: text, theirs: currentBody,
                                                     oursLabel: "yours", theirsLabel: "stored")
                    if result.hasConflicts {
                        throw MarginError.conflict(
                            "Note \(id) changed since version \(base.prefix(12)) in the same place",
                            ConflictDetail(path: r.path, currentVersion: version.hex, mergedText: result.text,
                                           conflictCount: result.conflictCount))
                    }
                    newBody = result.text
                    merged = true
                }
                let newContent = (fm?.render() ?? "") + newBody
                guard !sameBytes(newContent, content) else {
                    return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey)
                }
                let entry = ChangeSet.Entry(path: r.path, kind: .modified, noteID: id, beforeHash: version.hex,
                                            afterHash: ContentHash(of: newContent).hex, merged: merged ? true : nil)
                if dryRun { return finish(actor: actor, entries: [entry], dryRun: true, key: idempotencyKey) }
                do {
                    let store = self.store
                    return try await self.runTransaction(actor: actor, key: idempotencyKey) {
                        try await store.write(path, content: newContent, expectedVersion: version)
                        return [entry]
                    }
                } catch MarginError.conflict where attempt < Self.maxWriteAttempts {
                    continue   // another program changed the file since the read: start over with what it wrote
                }
            }
        }
    }

    /// Rewrites a note file through `transform` (whole content in, new content or `nil` out) with the
    /// usual write rules. Shared by the property write paths.
    func editContent(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?,
                     transform: (_ content: String, _ record: NoteRecord) throws -> String?) async throws -> ChangeSet {
        try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            var attempt = 0
            while true {
                attempt += 1
                let r = try await record(id)
                try requireWritable(path: r.path)
                let path = try VaultPath(r.path)
                let (content, version) = try await store.read(path)
                versions.remember(content, version: version.hex)
                try requireBaseVersion(baseVersion, matches: version.hex, what: "Note \(id)", path: r.path)
                guard let newContent = try transform(content, r), !sameBytes(newContent, content) else {
                    return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey)
                }
                let entry = ChangeSet.Entry(path: r.path, kind: .modified, noteID: id, beforeHash: version.hex,
                                            afterHash: ContentHash(of: newContent).hex)
                if dryRun { return finish(actor: actor, entries: [entry], dryRun: true, key: idempotencyKey) }
                do {
                    let store = self.store
                    return try await self.runTransaction(actor: actor, key: idempotencyKey) {
                        try await store.write(path, content: newContent, expectedVersion: version)
                        return [entry]
                    }
                } catch MarginError.conflict where attempt < Self.maxWriteAttempts {
                    continue
                }
            }
        }
    }

    func create(course courseID: CourseID, title: String, kind: NoteKind, text: String, actor: Actor,
                dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await writeGate.withLock {
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
            if dryRun { return finish(actor: actor, entries: [change], dryRun: true, key: idempotencyKey) }
            let store = self.store
            return try await self.runTransaction(actor: actor, key: idempotencyKey) {
                try await store.create(path, content: content)
                return [change]
            }
        }
    }

    func move(id: NoteID, toCourse target: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet {
        try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            let r = try await record(id)
            try requireWritable(path: r.path)
            guard let entry = model.entry(target) else { throw MarginError.notFound("No course \(target)") }
            try requireWritable(course: entry)
            let from = try VaultPath(r.path)
            let version = try await store.read(from).version
            try requireBaseVersion(baseVersion, matches: version.hex, what: "Note \(id)", path: r.path)
            let to = try VaultPath(components: [entry.semesterFolder, entry.folder, from.lastComponent])
            guard from != to else { return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey) }
            if await store.exists(to) { throw MarginError.conflict("\(to) already exists") }
            let change = ChangeSet.Entry(path: to.rawValue, kind: .moved, noteID: id, fromPath: from.rawValue,
                                         beforeHash: version.hex, afterHash: version.hex)
            if dryRun { return finish(actor: actor, entries: [change], dryRun: true, key: idempotencyKey) }
            let store = self.store
            // The rename triggers the link rewriting in other notes; those writes join the same
            // transaction, so undoing the move restores them too.
            return try await self.runTransaction(actor: actor, key: idempotencyKey) {
                try await store.rename(from, to: to)
                return [change]
            }
        }
    }

    func delete(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            let r = try await record(id)
            try requireWritable(path: r.path)
            let path = try VaultPath(r.path)
            let version = try await store.read(path).version
            try requireBaseVersion(baseVersion, matches: version.hex, what: "Note \(id)", path: r.path)
            let entry = ChangeSet.Entry(path: r.path, kind: .deleted, noteID: id, beforeHash: version.hex)
            if dryRun { return finish(actor: actor, entries: [entry], dryRun: true, key: idempotencyKey) }
            let store = self.store
            return try await self.runTransaction(actor: actor, key: idempotencyKey) {
                try await store.trash(path)
                return [entry]
            }
        }
    }

    // MARK: Tasks (write)

    /// Flips a task through `TaskWriteBack` (finds it again in the current file text, retries when the
    /// file changes meanwhile) inside one recorded transaction, so `TaskService.updates` fires and the
    /// toggle can be undone.
    func toggleTask(id taskID: String, actor: Actor, baseVersion: String?, dryRun: Bool,
                    idempotencyKey: String?) async throws -> ChangeSet {
        try TaskEditing.requireTask(id: taskID)
        return try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            var found: TaskItem?
            for record in await noteRecords() {
                if let task = record.tasks.first(where: { $0.id == taskID }) { found = task; break }
            }
            guard let item = found else { throw MarginError.notFound("No task \(taskID)") }
            let writeBack = taskWriteBack
            if dryRun {
                let result = try await writeBack.setDone(!item.done, task: item, baseVersion: baseVersion, dryRun: true)
                return finish(actor: actor, entries: result.entry.map { [$0] } ?? [], dryRun: true, key: idempotencyKey)
            }
            return try await self.runTransaction(actor: actor, key: idempotencyKey) {
                let result = try await writeBack.setDone(!item.done, task: item, baseVersion: baseVersion, dryRun: false)
                return result.entry.map { [$0] } ?? []
            }
        }
    }

    /// Sets or removes a task's due date through `TaskWriteBack`, as one recorded transaction like
    /// `toggleTask`.
    func setTaskDue(id taskID: String, due: LocalDate?, actor: Actor, baseVersion: String?, dryRun: Bool,
                    idempotencyKey: String?) async throws -> ChangeSet {
        try TaskEditing.requireTask(id: taskID)
        return try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            var found: TaskItem?
            for record in await noteRecords() {
                if let task = record.tasks.first(where: { $0.id == taskID }) { found = task; break }
            }
            guard let item = found else { throw MarginError.notFound("No task \(taskID)") }
            let writeBack = taskWriteBack
            if dryRun {
                let result = try await writeBack.setDue(due, task: item, baseVersion: baseVersion, dryRun: true)
                return finish(actor: actor, entries: result.entry.map { [$0] } ?? [], dryRun: true, key: idempotencyKey)
            }
            return try await self.runTransaction(actor: actor, key: idempotencyKey) {
                let result = try await writeBack.setDue(due, task: item, baseVersion: baseVersion, dryRun: false)
                return result.entry.map { [$0] } ?? []
            }
        }
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

    // MARK: Change sets

    func changes(limit: Int?) async -> [ChangeSet] { await journal.changes(limit: limit) }

    func change(id: String) async throws -> ChangeSet { try await journal.change(id: id) }

    func undo(id: String, actor: Actor, mode: UndoMode, dryRun: Bool) async throws -> ChangeSet {
        try await writeGate.withLock {
            let committed = try await journal.undo(id: id, actor: actor, mode: mode, dryRun: dryRun)
            await afterCommit(committed)
            return committed.changeSet
        }
    }

    /// A change set that is not recorded: a dry run, or a write that changed nothing.
    func finish(actor: Actor, entries: [ChangeSet.Entry], dryRun: Bool, key: String?) -> ChangeSet {
        let cs = changeSets.make(actor: actor, entries: entries, isDryRun: dryRun, idempotencyKey: key)
        if !dryRun { idempotency.remember(cs, actor: actor) }
        return cs
    }
}
