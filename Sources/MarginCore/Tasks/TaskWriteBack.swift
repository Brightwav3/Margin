import Foundation

/// The outcome of writing a task's checkbox back to its note.
public struct TaskWriteResult: Sendable, Hashable {
    /// The file change; `nil` when the task already had the wanted state (nothing was written).
    /// For a dry run this is the change that would happen.
    public var entry: ChangeSet.Entry?
    /// The task as it is (or, for a dry run, would be) in the file after the write.
    public var task: TaskItem
    /// Vault-relative path of the note file.
    public var path: String
    /// How the task was found on the last attempt.
    public var method: TaskMatch.Method
    /// Number of read-modify-write rounds needed (1 = no conflict).
    public var attempts: Int
}

/// Writes a task checkbox (`- [ ]` / `- [x]`) back to the note file it came from (M7-03).
///
/// Only the one character inside the brackets changes; every other byte of the file (BOM, CRLF,
/// frontmatter, other lines) stays as it was. The write is safe against edits made meanwhile:
///
/// 1. read the file and its version,
/// 2. find the task in *that* text with `TaskLocator` (`^id`, then text; the `TaskItem` may be
///    stale, lines may have shifted),
/// 3. write through `VaultStore` with `expectedVersion`,
/// 4. on `MarginError.conflict` (the file changed between read and write) start again at 1.
///
/// A task that cannot be found unambiguously is `MarginError.notFound`; the file is not touched.
/// Calls for the same note run one after another, so rapid toggles do not fight each other; a
/// conflict can then only come from another program.
///
/// `TaskService.toggle` (M6-11) is built on `setDone`. The caller applies the returned entry to a
/// `ChangeSet` and tells the `TasksStore` that the note changed.
public actor TaskWriteBack {
    /// Test seam: runs after each read, before the write (attempt number, 1-based).
    typealias Hook = @Sendable (Int) async -> Void

    private let store: VaultStore
    private let index: NoteIndex
    private let extractor: TaskExtractor
    private let maxAttempts: Int
    private let afterRead: Hook?
    private var busy: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]

    public init(store: VaultStore, index: NoteIndex, clock: any Clock, maxAttempts: Int = 5) {
        self.init(store: store, index: index, clock: clock, maxAttempts: maxAttempts, afterRead: nil)
    }

    init(store: VaultStore, index: NoteIndex, clock: any Clock, maxAttempts: Int = 5, afterRead: Hook?) {
        self.store = store; self.index = index
        self.extractor = TaskExtractor(clock: clock)
        self.maxAttempts = max(1, maxAttempts)
        self.afterRead = afterRead
    }

    /// Sets the checkbox of `task` to `done`.
    ///
    /// - Parameters:
    ///   - baseVersion: when given, the note must still have this version at the first read,
    ///     otherwise `.conflict` (the caller's view is stale and it asked not to be re-resolved).
    ///   - dryRun: computes the result and writes nothing.
    /// - Throws: `.invalid` for an exam, `.notFound` for an unknown note or a task that is no
    ///   longer there, `.conflict` when the file keeps changing (after `maxAttempts` rounds) or
    ///   `baseVersion` is stale, `.io` on disk errors.
    public func setDone(_ done: Bool, task: TaskItem, baseVersion: String? = nil,
                        dryRun: Bool = false) async throws -> TaskWriteResult {
        try await apply(task: task, baseVersion: baseVersion, dryRun: dryRun,
                        edit: { content, match in
                            guard let edited = Self.setting(done, in: content, task: match) else {
                                throw MarginError.invalid("Line \(match.line) of \(task.source.noteID) is not a checkbox")
                            }
                            return edited
                        },
                        adjust: { $0.done = done })
    }

    /// Sets or removes the due date of `task` (`DueDateWriter`): the `@…` token of the line is
    /// replaced or added, the `^id` stays at the end, nothing else in the file changes. Same safety
    /// as `setDone`: the task is found again in the current text, conflicts are retried.
    ///
    /// - Throws: as `setDone`, and `.invalid` when removing the date would leave the task without text.
    public func setDue(_ due: LocalDate?, task: TaskItem, baseVersion: String? = nil,
                       dryRun: Bool = false) async throws -> TaskWriteResult {
        let today = extractor.resolver.clock.today
        return try await apply(task: task, baseVersion: baseVersion, dryRun: dryRun,
                               edit: { content, match in try DueDateWriter.setting(due, in: content, task: match) },
                               adjust: { $0.due = due; $0.label = due.map { DueLabel.make(due: $0, today: today) } })
    }

    private func apply(task: TaskItem, baseVersion: String?, dryRun: Bool,
                       edit: (String, ExtractedTask) throws -> String,
                       adjust: (inout TaskItem) -> Void) async throws -> TaskWriteResult {
        guard task.kind == .task else { throw MarginError.invalid("\(task.text) is an exam, not a checkbox task") }
        let noteID = task.source.noteID
        guard let first = await index.note(byID: noteID) else { throw MarginError.notFound("No note \(noteID)") }
        await acquire(first.path)
        defer { release(first.path) }
        return try await attempt(task: task, baseVersion: baseVersion, dryRun: dryRun, edit: edit, adjust: adjust)
    }

    private func attempt(task: TaskItem, baseVersion: String?, dryRun: Bool,
                         edit: (String, ExtractedTask) throws -> String,
                         adjust: (inout TaskItem) -> Void) async throws -> TaskWriteResult {
        let target = TaskTarget(item: task)
        let noteID = task.source.noteID
        for round in 1...maxAttempts {
            guard let record = await index.note(byID: noteID) else { throw MarginError.notFound("No note \(noteID)") }
            let path = try VaultPath(record.path)
            let (content, version) = try await store.read(path)
            if round == 1, let baseVersion, baseVersion != version.hex {
                throw MarginError.conflict("Note \(noteID) changed since version \(baseVersion.prefix(12)) (now \(version.hex.prefix(12)))")
            }
            await afterRead?(round)

            guard let match = TaskLocator.resolve(target, in: extractor.extract(from: content)) else {
                throw MarginError.notFound("Task \"\(task.text)\" is no longer in \(noteID)")
            }
            var found = extractor.taskItem(match.task, noteID: noteID, courseID: task.source.courseID)
            let edited = try edit(content, match.task)
            adjust(&found)
            if edited == content {
                return TaskWriteResult(entry: nil, task: found, path: record.path, method: match.method, attempts: round)
            }
            let entry = ChangeSet.Entry(path: record.path, kind: .modified, noteID: noteID,
                                        beforeHash: version.hex, afterHash: ContentHash(of: edited).hex)
            if dryRun {
                return TaskWriteResult(entry: entry, task: found, path: record.path, method: match.method, attempts: round)
            }
            do {
                try await store.write(path, content: edited, expectedVersion: version)
            } catch MarginError.conflict {
                continue   // changed between read and write: look again
            }
            await index.update(path: record.path, content: edited)
            return TaskWriteResult(entry: entry, task: found, path: record.path, method: match.method, attempts: round)
        }
        throw MarginError.conflict("Note \(noteID) kept changing; the task was not written")
    }

    /// `content` with the checkbox of `task` set to `done`, changing exactly one byte; `nil` when the
    /// line does not start with a checkbox.
    static func setting(_ done: Bool, in content: String, task: ExtractedTask) -> String? {
        var bytes = Array(content.utf8)
        let range = task.range
        guard range.start >= 0, range.end <= bytes.count else { return nil }
        var i = range.start
        while i < range.end, bytes[i] != UInt8(ascii: "[") { i += 1 }
        guard i + 2 < range.end,
              bytes[i + 2] == UInt8(ascii: "]"),
              [UInt8(ascii: " "), UInt8(ascii: "x"), UInt8(ascii: "X")].contains(bytes[i + 1]) else { return nil }
        let isDone = bytes[i + 1] != UInt8(ascii: " ")
        if isDone == done { return content }
        bytes[i + 1] = done ? UInt8(ascii: "x") : UInt8(ascii: " ")
        return String(validating: bytes, as: UTF8.self)
    }

    // MARK: Per-note queue

    private func acquire(_ path: String) async {
        if busy.contains(path) {
            await withCheckedContinuation { waiting[path, default: []].append($0) }
            return   // the releasing call handed the slot over; `busy` stays set
        }
        busy.insert(path)
    }

    private func release(_ path: String) {
        if var queue = waiting[path], !queue.isEmpty {
            let next = queue.removeFirst()
            waiting[path] = queue.isEmpty ? nil : queue
            next.resume()
        } else {
            busy.remove(path)
        }
    }
}
