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
    let store: VaultStore
    let index: NoteIndex
    let clock: any Clock
    let journal: ChangeSetJournal

    nonisolated let noteChanges = Broadcaster<[NoteChange]>()
    nonisolated let catalogUpdates = Broadcaster<CatalogUpdate>()

    private(set) var model = VaultCourseModel()
    private var changeSets: ChangeSetFactory
    private var idempotency = IdempotencyCache()
    private var versions = TextVersionCache()
    private let writeGate = AsyncMutex()
    private let rewriter = WikilinkRewriter()
    private var watchTask: Task<Void, Never>?

    /// How often a write is retried against a newer stored version when another program changes
    /// the file between the read and the write.
    private static let maxWriteAttempts = 6

    private init(store: VaultStore, index: NoteIndex, clock: any Clock, journal: ChangeSetJournal) {
        self.store = store; self.index = index; self.clock = clock; self.journal = journal
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
    static func open(at url: URL, clock: any Clock, watchInterval: TimeInterval = 0.3,
                     retention: ChangeSetRetention = .standard,
                     fileSystem: any FileSystem = POSIXFileSystem()) async throws -> VaultBackend {
        // A generous TTL: on a busy machine the poller may lag far behind the app's own writes.
        let ownWrites = OwnWriteRegistry(ttl: 60)
        let store = try await VaultStore.open(root: url, fileSystem: fileSystem, clock: clock, ownWrites: ownWrites)
        let journal = try await ChangeSetJournal.open(store: store, clock: clock, retention: retention)
        let index = NoteIndex(clock: clock)
        try await index.build(from: VaultNoteSource(store: store))
        let backend = VaultBackend(store: store, index: index, clock: clock, journal: journal)
        await store.addRenameObserver(backend.rewriter)
        await backend.reloadModel()
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
            let old = model.courses
            await reloadModel()
            let changed = Self.changedCourses(old: old, new: model.courses)
            if !changed.isEmpty { catalogUpdates.send(CatalogUpdate(courses: changed)) }
        }
        if !notes.isEmpty { noteChanges.send(notes.sorted { ($0.noteID, $0.kind.rawValue) < ($1.noteID, $1.kind.rawValue) }) }
    }

    private static func changedCourses(old: [Course], new: [Course]) -> [CourseID] {
        let before = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
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

    private func courseID(of record: NoteRecord) -> CourseID? {
        model.courseID(semesterFolder: record.semesterID, folder: record.courseID, className: record.className)
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
        guard let r = await index.note(byID: id), Self.isNotePath(r.path) else { throw MarginError.notFound("No note \(id)") }
        return r
    }

    // MARK: Courses

    func semesters() -> [Semester] { model.semesters }

    private func currentSemester() -> Semester? { ServiceRules.currentSemester(model.semesters, today: clock.today) }

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
        return try ServiceRules.occurrences(week: week, semester: current, courses: model.courses.filter { $0.semester == current.id })
    }

    // MARK: Notes (read)

    func notes(course: CourseID?) async throws -> [NoteSummary] {
        if let course { _ = try self.course(id: course) }
        let all = await noteRecords().map { summary(of: $0) }
        return ServiceRules.sortNotes(all.filter { course == nil || $0.courseID == course })
    }

    func open(id: NoteID) async throws -> Note {
        let r = try await record(id)
        let (content, version) = try await store.read(VaultPath(r.path))
        versions.remember(content, version: version.hex)
        // Reading is the moment the index catches up with what is on disk.
        await index.update(path: r.path, content: content)
        let fresh = await index.note(byPath: r.path) ?? r
        return Note(summary: summary(of: fresh), text: Frontmatter.parse(content).body, version: version.hex)
    }

    // MARK: Tasks (read)

    private func allTasks(course: CourseID? = nil) async -> [TaskItem] {
        var items: [TaskItem] = []
        for r in await noteRecords() {
            guard let cid = courseID(of: r), course == nil || cid == course else { continue }
            items += r.tasks.map { var t = $0; t.source.courseID = cid; return t }
        }
        return items
    }

    func today() async -> [TaskItem] {
        ServiceRules.todayItems(tasks: await allTasks(), exams: ServiceRules.examItems(model.courses), today: clock.today)
    }

    func upcoming() async -> [TaskItem] {
        ServiceRules.upcomingItems(tasks: await allTasks(), exams: ServiceRules.examItems(model.courses), today: clock.today)
    }

    func tasks(course id: CourseID) async throws -> [TaskItem] {
        _ = try course(id: id)
        return ServiceRules.courseTasks(await allTasks(course: id), today: clock.today)
    }

    // MARK: Notes (write)

    /// Applies the operations a committed transaction performed to the index and the version cache.
    private func afterCommit(_ committed: ChangeSetJournal.Committed) async {
        for op in committed.operations {
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
                if let from = op.fromPath { await index.rename(from: from, to: op.path) }
            case .trash:
                await index.remove(path: op.path)
            }
        }
    }

    /// Identifies the note at a vault path, for change-set entries of files a write touched
    /// indirectly (notes whose links a move rewrote).
    private func noteID(atPath path: String) async -> NoteID? { await index.note(byPath: path)?.id }

    func save(id: NoteID, text: String, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet {
        try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            var attempt = 0
            while true {
                attempt += 1
                let r = try await record(id)
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
                    let committed = try await journal.transaction(
                        actor: actor, idempotencyKey: idempotencyKey, noteID: { [weak self] in await self?.noteID(atPath: $0) },
                        body: {
                            try await store.write(path, content: newContent, expectedVersion: version)
                            return [entry]
                        })
                    await afterCommit(committed)
                    idempotency.remember(committed.changeSet, actor: actor)
                    return committed.changeSet
                } catch MarginError.conflict where attempt < Self.maxWriteAttempts {
                    continue   // another program changed the file since the read: start over with what it wrote
                }
            }
        }
    }

    func create(course courseID: CourseID, title: String, kind: NoteKind, text: String, actor: Actor,
                dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            guard let entry = model.entry(courseID) else { throw MarginError.notFound("No course \(courseID)") }
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
            let committed = try await journal.transaction(
                actor: actor, idempotencyKey: idempotencyKey, noteID: { [weak self] in await self?.noteID(atPath: $0) },
                body: {
                    try await store.create(path, content: content)
                    return [change]
                })
            await afterCommit(committed)
            idempotency.remember(committed.changeSet, actor: actor)
            return committed.changeSet
        }
    }

    func move(id: NoteID, toCourse target: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
              idempotencyKey: String?) async throws -> ChangeSet {
        try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            let r = try await record(id)
            guard let entry = model.entry(target) else { throw MarginError.notFound("No course \(target)") }
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
            let committed = try await journal.transaction(
                actor: actor, idempotencyKey: idempotencyKey, noteID: { [weak self] in await self?.noteID(atPath: $0) },
                body: {
                    try await store.rename(from, to: to)
                    return [change]
                })
            await afterCommit(committed)
            idempotency.remember(committed.changeSet, actor: actor)
            return committed.changeSet
        }
    }

    func delete(id: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await writeGate.withLock {
            if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
            let r = try await record(id)
            let path = try VaultPath(r.path)
            let version = try await store.read(path).version
            try requireBaseVersion(baseVersion, matches: version.hex, what: "Note \(id)", path: r.path)
            let entry = ChangeSet.Entry(path: r.path, kind: .deleted, noteID: id, beforeHash: version.hex)
            if dryRun { return finish(actor: actor, entries: [entry], dryRun: true, key: idempotencyKey) }
            let store = self.store
            let committed = try await journal.transaction(
                actor: actor, idempotencyKey: idempotencyKey, noteID: { [weak self] in await self?.noteID(atPath: $0) },
                body: {
                    try await store.trash(path)
                    return [entry]
                })
            await afterCommit(committed)
            idempotency.remember(committed.changeSet, actor: actor)
            return committed.changeSet
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
    private func finish(actor: Actor, entries: [ChangeSet.Entry], dryRun: Bool, key: String?) -> ChangeSet {
        let cs = changeSets.make(actor: actor, entries: entries, isDryRun: dryRun, idempotencyKey: key)
        if !dryRun { idempotency.remember(cs, actor: actor) }
        return cs
    }
}
