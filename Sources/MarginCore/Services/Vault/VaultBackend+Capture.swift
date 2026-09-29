import Foundation

/// `CaptureService` on a vault (spec 05 §6, §3). The layout rules are in `CaptureRules`.
extension VaultBackend {
    func captureParse(_ input: String) async -> CaptureDraft {
        let notes = await index.allNotes.filter { Self.isNotePath($0.path) }.map { r -> NoteSummary in
            var s = r.summary
            s.courseID = model.courseID(semesterFolder: r.semesterID, folder: r.courseID, className: r.className)
            return s
        }
        let current = ServiceRules.currentSemester(model.semesters, today: clock.today)
        let courses = model.courses.filter { $0.semester == current?.id }
        return QuickCaptureParser(courses: courses, clock: clock, notes: notes).parse(input).draft
    }

    func captureCommit(_ draft: CaptureDraft, actor: Actor, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let text = try CaptureRules.validatedText(draft.text)
        let entry: ChangeSet.Entry
        if let target = draft.attachTo {
            guard let record = await index.note(byID: target), Self.isNotePath(record.path) else {
                throw MarginError.notFound("No note \(target)")
            }
            entry = try await append(draft, text: text, toFile: VaultPath(record.path), noteID: target, dryRun: dryRun)
        } else if let courseID = draft.course {
            guard let course = model.entry(courseID) else { throw MarginError.notFound("No course \(courseID)") }
            entry = draft.kind == .task
                ? try await appendToTasksNote(course, draft: draft, text: text, dryRun: dryRun)
                : try await createCourseNote(course, draft: draft, text: text, dryRun: dryRun)
        } else {
            entry = try await createInboxFile(draft, text: text, dryRun: dryRun)
        }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }

    // MARK: Building blocks (shared with triage)

    /// A task id and a note id not used anywhere in the vault.
    func freshIDs() async -> (task: String, note: String, used: Set<String>) {
        let records = await index.allNotes
        var used = Set(records.flatMap { $0.tasks.map(\.id) })
        used.formUnion(records.map(\.id))
        var generator = StableIDGenerator()
        let task = generator.next(.task, avoiding: used)
        let note = generator.next(.note, avoiding: used.union([task]))
        return (task, note, used)
    }

    /// Reads `path`, applies `transform`, writes with the version that was read (a change made
    /// meanwhile is `.conflict` and the step starts again, up to 3 times). Returns the entry.
    func modify(_ path: VaultPath, noteID: NoteID?, dryRun: Bool,
                _ transform: (String) throws -> String) async throws -> ChangeSet.Entry {
        var attempt = 0
        while true {
            attempt += 1
            let (content, version) = try await store.read(path)
            let updated = try transform(content)
            let entry = ChangeSet.Entry(path: path.rawValue, kind: .modified, noteID: noteID, beforeHash: version.hex,
                                        afterHash: ContentHash(of: updated).hex)
            if dryRun { return entry }
            do {
                try await store.write(path, content: updated, expectedVersion: version)
            } catch let e as MarginError {
                if e.code == "conflict", attempt < 3 { continue }
                throw e
            }
            await index.update(path: path.rawValue, content: updated)
            await tasksMayHaveChanged(paths: [path.rawValue])
            return entry
        }
    }

    private func append(_ draft: CaptureDraft, text: String, toFile path: VaultPath, noteID: NoteID?,
                        dryRun: Bool) async throws -> ChangeSet.Entry {
        let ids = await freshIDs()
        return try await modify(path, noteID: noteID, dryRun: dryRun) { content in
            draft.kind == .task
                ? CaptureRules.append(line: CaptureRules.taskLine(text: text, tags: draft.tags, due: draft.due, id: ids.task), to: content)
                : CaptureRules.append(paragraph: text, to: content)
        }
    }

    /// Appends a task line to `<course>/Tasks.md`, creating the note when it is missing.
    func appendTaskLine(_ line: (String) -> String, course: VaultCourseModel.Entry, dryRun: Bool) async throws -> ChangeSet.Entry {
        let path = try VaultPath(components: [course.semesterFolder, course.folder, CaptureRules.tasksNoteTitle + ".md"])
        let ids = await freshIDs()
        if await store.exists(path) {
            let noteID = await index.note(byPath: path.rawValue)?.id
            return try await modify(path, noteID: noteID, dryRun: dryRun) { CaptureRules.append(line: line(ids.task), to: $0) }
        }
        let content = CaptureRules.tasksNoteFile(id: ids.note, courseName: course.course.name, line: line(ids.task))
        let entry = ChangeSet.Entry(path: path.rawValue, kind: .created, noteID: ids.note, afterHash: ContentHash(of: content).hex)
        if !dryRun {
            try await store.create(path, content: content)
            await index.update(path: path.rawValue, content: content)
            await tasksMayHaveChanged(paths: [path.rawValue])
        }
        return entry
    }

    private func appendToTasksNote(_ course: VaultCourseModel.Entry, draft: CaptureDraft, text: String,
                                   dryRun: Bool) async throws -> ChangeSet.Entry {
        try await appendTaskLine({ CaptureRules.taskLine(text: text, tags: draft.tags, due: draft.due, id: $0) },
                                 course: course, dryRun: dryRun)
    }

    /// Creates a note in a course folder from capture text (title taken: ` 2`, ` 3`, …).
    func createNote(in course: VaultCourseModel.Entry, text: String, tags: [String], date: LocalDate,
                    dryRun: Bool) async throws -> ChangeSet.Entry {
        let base = CaptureRules.title(from: text)
        var title = base
        var n = 2
        var path = try VaultPath(components: [course.semesterFolder, course.folder, VaultPath.filename(fromTitle: title) + ".md"])
        while await store.exists(path) {
            title = "\(base) \(n)"; n += 1
            path = try VaultPath(components: [course.semesterFolder, course.folder, VaultPath.filename(fromTitle: title) + ".md"])
        }
        let id = await freshIDs().note
        let content = CaptureRules.noteFile(id: id, courseName: course.course.name, date: date, tags: tags, title: title, text: text)
        let entry = ChangeSet.Entry(path: path.rawValue, kind: .created, noteID: id, afterHash: ContentHash(of: content).hex)
        if !dryRun {
            try await store.create(path, content: content)
            await index.update(path: path.rawValue, content: content)
            await tasksMayHaveChanged(paths: [path.rawValue])
        }
        return entry
    }

    private func createCourseNote(_ course: VaultCourseModel.Entry, draft: CaptureDraft, text: String,
                                  dryRun: Bool) async throws -> ChangeSet.Entry {
        try await createNote(in: course, text: text, tags: draft.tags, date: clock.today, dryRun: dryRun)
    }

    /// The stem, or the stem with ` 2`, ` 3`, … when an inbox file of that name exists.
    func freeInboxStem(_ stem: String) async -> String {
        var candidate = stem
        var n = 2
        while let p = try? VaultPath(components: [CaptureRules.inboxFolder, candidate + ".md"]), await store.exists(p) {
            candidate = "\(stem) \(n)"; n += 1
        }
        return candidate
    }

    private func createInboxFile(_ draft: CaptureDraft, text: String, dryRun: Bool) async throws -> ChangeSet.Entry {
        let captured = clock.localNow
        let stem = await freeInboxStem(CaptureRules.inboxStem(captured: captured, text: text))
        let item = InboxItem(id: stem, text: CaptureRules.inboxBody(draft, text: text), kind: draft.kind,
                             source: .quickCapture, captured: captured)
        let content = CaptureRules.inboxFile(item)
        let path = try VaultPath(components: [CaptureRules.inboxFolder, stem + ".md"])
        if !dryRun { try await store.create(path, content: content) }
        return .init(path: path.rawValue, kind: .created, afterHash: ContentHash(of: content).hex)
    }
}
