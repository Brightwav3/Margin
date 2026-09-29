import Foundation

/// `CaptureService` on the fixture world. Same rules as `VaultBackend` (see `CaptureRules`).
extension FixtureStore {
    func captureParse(_ input: String) -> CaptureDraft {
        let notes = self.notes.values.map(\.summary)
        return QuickCaptureParser(courses: courses, clock: clock, notes: notes).parse(input).draft
    }

    func captureCommit(_ draft: CaptureDraft, actor: Actor, dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let text = try CaptureRules.validatedText(draft.text)
        var entries: [ChangeSet.Entry] = []
        var changedNote: StoredNote?
        var newInbox: (item: InboxItem, stem: String)?

        if let target = draft.attachTo {
            guard let note = notes[target] else { throw MarginError.notFound("No note \(target)") }
            let (updated, entry) = try appendCapture(draft, text: text, to: note)
            (changedNote, entries) = (updated, [entry])
        } else if let courseID = draft.course {
            let course = try self.course(id: courseID)
            if draft.kind == .task {
                let (updated, entry) = try appendToTasksNote(course: course, text: text, tags: draft.tags, due: draft.due)
                (changedNote, entries) = (updated, [entry])
            } else {
                let (created, entry) = newCourseNote(course: course, text: text, date: clock.today)
                (changedNote, entries) = (created, [entry])
            }
        } else {
            let captured = clock.localNow
            let stem = CaptureRules.freeStem(CaptureRules.inboxStem(captured: captured, text: text)) { s in
                inboxStems.values.contains(s)
            }
            let item = InboxItem(id: stem, text: CaptureRules.inboxBody(draft, text: text), kind: draft.kind,
                                 source: .quickCapture, captured: captured)
            newInbox = (item, stem)
            entries = [.init(path: "\(CaptureRules.inboxFolder)/\(stem).md", kind: .created,
                             afterHash: ContentHash(of: CaptureRules.inboxFile(item)).hex)]
        }
        if !dryRun {
            if let n = changedNote { notes[n.summary.id] = n }
            if let (item, stem) = newInbox { inbox.append(item); inboxStems[item.id] = stem }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    // MARK: Pieces

    func newTaskID() -> String {
        var generator = StableIDGenerator()
        return generator.next(.task, avoiding: Set(allTasks().map(\.id)))
    }

    private func appendCapture(_ draft: CaptureDraft, text: String, to note: StoredNote) throws -> (StoredNote, ChangeSet.Entry) {
        let before = Self.version(of: note.content)
        var updated = note
        if draft.kind == .task {
            updated.body = CaptureRules.append(line: CaptureRules.taskLine(text: text, tags: draft.tags, due: draft.due, id: newTaskID()),
                                               to: note.body)
        } else {
            updated.body = CaptureRules.append(paragraph: text, to: note.body)
        }
        updated.summary = summarize(updated)
        return (updated, .init(path: path(of: updated), kind: .modified, noteID: note.summary.id,
                               beforeHash: before, afterHash: Self.version(of: updated.content)))
    }

    /// Appends a task line to `<course>/tasks` (creating the note when missing).
    func appendToTasksNote(course: Course, text: String, tags: [String], due: LocalDate?) throws -> (StoredNote, ChangeSet.Entry) {
        let id = ServiceRules.noteID(course: course.id, title: CaptureRules.tasksNoteTitle)
        let line = CaptureRules.taskLine(text: text, tags: tags, due: due, id: newTaskID())
        if let existing = notes[id] {
            let before = Self.version(of: existing.content)
            var updated = existing
            updated.body = CaptureRules.append(line: line, to: existing.body)
            updated.summary = summarize(updated)
            return (updated, .init(path: path(of: updated), kind: .modified, noteID: id, beforeHash: before,
                                   afterHash: Self.version(of: updated.content)))
        }
        var note = StoredNote(summary: NoteSummary(id: id, courseID: course.id, title: CaptureRules.tasksNoteTitle, kind: .note),
                              fileTitle: CaptureRules.tasksNoteTitle,
                              frontmatter: Self.newFrontmatter(id: id, course: course, kind: .note),
                              body: "# \(CaptureRules.tasksNoteTitle)\n\n\(line)\n")
        note.summary = summarize(note)
        return (note, .init(path: path(of: note), kind: .created, noteID: id, afterHash: Self.version(of: note.content)))
    }

    /// A new note in the course, titled after the first line of `text`.
    func newCourseNote(course: Course, text: String, date: LocalDate) -> (StoredNote, ChangeSet.Entry) {
        let base = CaptureRules.title(from: text)
        var title = base
        var n = 2
        while notes[ServiceRules.noteID(course: course.id, title: title)] != nil || fileNameTaken(title, in: course.id, except: nil) {
            title = "\(base) \(n)"; n += 1
        }
        let id = ServiceRules.noteID(course: course.id, title: title)
        var note = StoredNote(summary: NoteSummary(id: id, courseID: course.id, title: title, kind: .note),
                              fileTitle: title, frontmatter: Self.newFrontmatter(id: id, course: course, kind: .note),
                              body: CaptureRules.noteBody(title: title, text: text))
        note.summary = summarize(note)
        note.summary.date = date
        return (note, .init(path: path(of: note), kind: .created, noteID: id, afterHash: Self.version(of: note.content)))
    }
}
