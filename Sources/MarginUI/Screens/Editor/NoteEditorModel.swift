import MarginCore
import Observation
import SwiftUI

/// One open note (3a): its text, saving, mode, and the facts shown around the editor (properties,
/// status bar, inspector). A draft is a class without a note; it becomes the note on first write.
@MainActor @Observable
public final class NoteEditorModel {
    public enum Target: Sendable, Hashable {
        case note(NoteID)
        case draft(course: CourseID, date: LocalDate, title: String)
    }

    public private(set) var target: Target
    public private(set) var summary: NoteSummary?
    /// The editor's text. Set by the text view on every keystroke.
    public private(set) var text: String = ""
    /// Bumped when the text changes from outside the text view (load, merge, property edit).
    public private(set) var revision = 0
    public var mode: EditorMode = .live
    /// Edit mode to return to from reading.
    private var lastEditMode: EditorMode = .live
    public var readableLineLength = true
    /// Settings › Editor › Show properties.
    public var showsProperties = true
    /// Note › Add property (⌘;): the properties panel opens its add popover.
    public var requestAddProperty = false
    /// Bumped to restyle after View › Zoom.
    public private(set) var styleRevision = 0

    func restyle() { styleRevision += 1 }
    public private(set) var isLoaded = false
    public private(set) var saving = false
    public private(set) var lastSaved: LocalDateTime?
    public private(set) var error: String?

    public private(set) var properties: [NoteProperty] = []
    public private(set) var outline: [OutlineItem] = []
    public private(set) var backlinks: [NoteBacklink] = []
    public private(set) var outgoing: [OutgoingLink] = []
    public private(set) var stats = NoteStats(backlinks: 0, properties: 0, words: 0, openTasks: 0, totalTasks: 0)
    public private(set) var propertyTypes: [String: PropertyType] = [:]

    private let env: AppEnvironment
    private var version: String?
    private var saveTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    /// Debounce before a save (M6-01: 400 ms).
    static let saveDelay: Duration = .milliseconds(400)

    public init(env: AppEnvironment, target: Target) {
        self.env = env
        self.target = target
    }

    public var noteID: NoteID? { if case .note(let id) = target { id } else { nil } }
    public var isDraft: Bool { noteID == nil }

    public var courseID: CourseID? {
        switch target {
        case .note: summary?.courseID
        case .draft(let course, _, _): course
        }
    }

    public var title: String {
        switch target {
        case .note: summary?.title ?? ""
        case .draft(_, _, let title): title
        }
    }

    // MARK: Loading

    public func load() async {
        switch target {
        case .note(let id):
            do {
                let note = try await env.notes.open(id: id)
                summary = note.summary
                version = note.version
                if note.text != text { text = note.text; revision += 1 }
                onLoaded?(note.summary)
                propertyTypes = (try? await env.properties.types()) ?? [:]
                await refreshFacts()
            } catch {
                self.error = Workspace.describe(error)
            }
        case .draft(_, let date, let title):
            if !isLoaded {
                text = "# \(title)\n\n"
                revision += 1
                _ = date
            }
        }
        isLoaded = true
    }

    /// Picks up edits made outside Margin (another editor, sync) when nothing is pending here.
    public func observeExternalChanges() async {
        for await changes in env.notes.externalChanges {
            guard ExternalChanges.followed else { continue }
            guard let id = noteID, changes.contains(where: { $0.noteID == id }), saveTask == nil else { continue }
            if changes.contains(where: { $0.noteID == id && $0.kind == .deleted }) {
                error = "This note was deleted outside Margin."
                continue
            }
            await load()
        }
    }

    private func refreshFacts() async {
        guard let id = noteID else { return }
        properties = (try? await env.analysis.properties(id: id)) ?? []
        outline = (try? await env.analysis.outline(id: id)) ?? []
        backlinks = (try? await env.analysis.backlinks(id: id)) ?? []
        outgoing = (try? await env.analysis.outgoing(id: id)) ?? []
        if let s = try? await env.analysis.stats(id: id, text: text) { stats = s }
    }

    // MARK: Editing

    /// Called by the text view after every change.
    public func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        scheduleSave()
        scheduleStats()
    }

    /// Replaces the text from outside the text view (undoable edits go through the text view).
    func replaceText(_ newText: String) {
        text = newText
        revision += 1
        scheduleSave()
        scheduleStats()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            await self.save()
        }
    }

    /// Status bar numbers follow the text within 200 ms (M6-08).
    private func scheduleStats() {
        statsTask?.cancel()
        statsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            if let id = self.noteID {
                if let s = try? await self.env.analysis.stats(id: id, text: self.text) { self.stats = s }
            } else {
                self.stats = NoteStats(backlinks: 0, properties: 0,
                                       words: self.text.split { $0.isWhitespace || $0.isNewline }.count,
                                       openTasks: 0, totalTasks: 0)
            }
        }
    }

    /// Saves now (tab close, window close, mode switch).
    public func flush() async {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        await save()
    }

    /// Callback after the note loaded (the tab takes its title).
    var onLoaded: ((NoteSummary) -> Void)?

    /// Callback when a draft became a note (the workspace retargets the tab).
    var onCreated: ((NoteSummary) -> Void)?

    private func save() async {
        saveTask = nil
        saving = true
        defer { saving = false }
        do {
            switch target {
            case .note(let id):
                _ = try await env.notes.save(id: id, text: text, actor: .user, baseVersion: version, dryRun: false,
                                             idempotencyKey: nil)
                version = try await env.notes.open(id: id).version
            case .draft(let course, let date, let title):
                let change = try await env.notes.create(course: course, title: title, kind: .lecture, text: text,
                                                        actor: .user, baseVersion: nil, dryRun: false,
                                                        idempotencyKey: "draft-\(course)-\(date.iso)")
                guard let id = change.entries.first?.noteID else { return }
                // The class date ties the note to its session (spec 05: lecture notes carry `date:`).
                _ = try? await env.properties.set(key: "date", value: .date(date), on: id, actor: .user,
                                                  baseVersion: nil, dryRun: false, idempotencyKey: nil)
                target = .note(id)
                let note = try await env.notes.open(id: id)
                summary = note.summary
                version = note.version
                if note.text != text { text = note.text; revision += 1 }
                onCreated?(note.summary)
            }
            lastSaved = env.clock.localNow
            error = nil
            await refreshFacts()
        } catch let e as MarginError {
            if case .conflict(_, let detail) = e, let merged = detail?.mergedText, let current = detail?.currentVersion {
                // Edited elsewhere too: take the three-way merge and save it on top of their version.
                version = current
                replaceText(merged)
                error = (detail?.conflictCount ?? 0) > 0 ? "Merged with changes made elsewhere; check the conflict markers." : nil
            } else if case .conflict = e, let id = noteID, let current = try? await env.notes.open(id: id) {
                version = current.version
                error = "This note changed elsewhere. Your text is kept; saving again overwrites theirs."
            } else {
                error = e.message
            }
        } catch {
            self.error = Workspace.describe(error)
        }
    }

    // MARK: Modes

    public func toggleReading() {
        if mode == .reading { mode = lastEditMode } else { lastEditMode = mode; mode = .reading }
    }

    public func setMode(_ m: EditorMode) {
        if m != .reading { lastEditMode = m }
        mode = m
    }

    // MARK: Properties (M6-05.U)

    public func setProperty(_ key: String, _ value: FrontmatterValue) async {
        guard let id = noteID else { return }
        await flush()
        do {
            _ = try await env.properties.set(key: key, value: value, on: id, actor: .user, baseVersion: version,
                                             dryRun: false, idempotencyKey: nil)
            await load()
        } catch {
            self.error = Workspace.describe(error)
        }
    }

    public func removeProperty(_ key: String) async {
        guard let id = noteID else { return }
        await flush()
        do {
            _ = try await env.properties.remove(key: key, on: id, actor: .user, baseVersion: version, dryRun: false,
                                                idempotencyKey: nil)
            await load()
        } catch {
            self.error = Workspace.describe(error)
        }
    }

    /// „Edited 10:24“.
    public var editedLine: String {
        if saving { return "Saving…" }
        let when = lastSaved ?? summary?.modified
        guard let when else { return isDraft ? "Not saved yet" : "" }
        if when.date == env.clock.today { return "Edited \(CoursesFormat.hour(when.time))" }
        return "Edited \(CourseDetailModel.day(when.date))"
    }
}

extension FrontmatterValue {
    /// Text shown in the Properties panel.
    var display: String {
        switch self {
        case .null: ""
        case .bool(let b): b ? "Yes" : "No"
        case .number(let n): n.rounded() == n ? String(Int(n)) : String(n)
        case .string(let s): s
        case .date(let d): String(format: "%02d.%02d.%04d", d.day, d.month, d.year)
        case .dateTime(let dt): "\(dt.date.day).\(dt.date.month).\(dt.date.year) \(dt.time.string)"
        case .list(let items): items.map(\.display).joined(separator: ", ")
        case .map(let pairs): pairs.map { "\($0.key): \($0.value.display)" }.joined(separator: ", ")
        }
    }
}
