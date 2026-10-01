import AppKit
import MarginCore
import UniformTypeIdentifiers

/// What the menu bar (M10-34…36) asks of the window: the open editor, views, navigation.
extension Workspace {
    // MARK: Active editor

    /// The editor of the active tab, set by the note page while it is shown.
    public var editor: NoteEditorModel? { activeEditor.model }
    public var hasEditor: Bool { activeEditor.model != nil && activeEditor.handle?.textView != nil }
    public var canEditText: Bool { hasEditor && editor?.mode != .reading }

    func setActiveEditor(_ model: NoteEditorModel?, handle: EditorHandle?) {
        activeEditor = ActiveEditor(model: model, handle: handle)
    }

    public func format(_ style: EditorInline) { activeEditor.handle?.toggle(style) }
    public func format(_ block: EditorBlock) { activeEditor.handle?.setBlock(block) }
    public func insert(_ what: EditorInsertion) { activeEditor.handle?.insert(what, clock: env.clock) }
    public func indentSelection() { activeEditor.handle?.indent() }
    public func outdentSelection() { activeEditor.handle?.outdent() }
    public func clearFormatting() { activeEditor.handle?.clearFormatting() }
    public func copyAsMarkdown() { activeEditor.handle?.copyAsMarkdown() }
    public func pasteAsPlainText() { activeEditor.handle?.pasteAsPlainText() }
    public func findInNote(replace: Bool) { activeEditor.handle?.find(replace: replace) }

    // MARK: View

    public var isReading: Bool { editor?.mode == .reading }
    public var isSource: Bool { editor?.mode == .source }
    public func toggleReading() { editor?.toggleReading() }
    public func toggleSource() { if let e = editor { e.setMode(e.mode == .source ? .live : .source) } }

    public var showsProperties: Bool { editorDefaults.showProperties }
    public func toggleProperties() {
        editorDefaults.showProperties.toggle()
        for m in editorModels { m.showsProperties = editorDefaults.showProperties }
        let v = editorDefaults.showProperties
        Task { try? await env.settings.set(Settings.showProperties, v) }
    }

    public var readableLineLength: Bool { editorDefaults.readableLineLength }
    public func toggleReadableLineLength() {
        editorDefaults.readableLineLength.toggle()
        for m in editorModels { m.readableLineLength = editorDefaults.readableLineLength }
        let v = editorDefaults.readableLineLength
        Task { try? await env.settings.set(Settings.readableLineLength, v) }
    }

    public var textZoom: CGFloat { MarkdownStyler.scale }

    /// ⌘+ / ⌘− / ⌘0: text size of every editor (0.7…2).
    public func zoomText(_ step: Int) {
        MarkdownStyler.scale = step == 0 ? 1 : min(2, max(0.7, MarkdownStyler.scale + CGFloat(step) * 0.1))
        for m in editorModels { m.restyle() }
    }

    var editorModels: [NoteEditorModel] { allModels.compactMap { $0 as? NoteEditorModel } }

    // MARK: File

    /// ⌃⌘N: the next class of the current course as a draft note, else a new note.
    public func newLectureNote() {
        guard let course = currentCourse ?? courses.cards.first?.id else { dialog = .newCourse; return }
        let m = courseModel(course)
        Task { @MainActor in
            if !m.isLoaded { await m.load() }
            if let next = m.upcoming.first(where: { o in !m.notes.contains { $0.date == o.date } }) {
                open(session: next)
            } else {
                newNote(in: m)
            }
        }
    }

    public var currentNote: NoteSummary? { editor?.summary }
    public func shareCurrentNote() { if let n = currentNote { dialog = .share(n) } }
    public func moveCurrentNote() { if let n = currentNote { dialog = .moveNote(n) } }
    public func deleteCurrentNote() { if let n = currentNote { dialog = .deleteNote(n) } }
    public func historyOfCurrentNote() { if let id = editor?.noteID { dialog = .history(id) } }
    public func closeActiveTab() { if let id = shell.activeTabID { shell.close(id) } }

    /// Recently opened notes, newest first (File › Open recent).
    public var recentNotes: [(id: NoteID, title: String)] { recents }

    func remember(note id: NoteID, title: String) {
        recents.removeAll { $0.id == id }
        recents.insert((id, title), at: 0)
        if recents.count > 10 { recents.removeLast() }
    }

    public func openRecent(_ id: NoteID, title: String) { open(.note(id), title: title) }

    // MARK: Note

    /// Adds the `revision` tag (Note › Add to revision).
    public func addCurrentNoteToRevision() {
        guard let e = editor else { return }
        var tags: [FrontmatterValue] = []
        if case .list(let old)? = e.properties.first(where: { $0.key == "tags" })?.value { tags = old }
        guard !tags.contains(.string("revision")) else { show("Already in revision"); return }
        tags.append(.string("revision"))
        Task { await e.setProperty("tags", .list(tags)); show("Added to revision", icon: "sell") }
    }

    public func addPropertyToCurrentNote() { editor?.requestAddProperty = true }
    public func showBacklinks() { shell.inspectorOpen = true; shell.inspectorTab = .backlinks }

    // MARK: Go

    public var canGoBack: Bool { shell.canGoBack }
    public var canGoForward: Bool { shell.canGoForward }
    public func goBack() { shell.goBack() }
    public func goForward() { shell.goForward() }
    public func nextTab() { shell.cycleTab(1) }
    public func previousTab() { shell.cycleTab(-1) }

    /// ⌃⌘→ / ⌃⌘←: the next or previous dated note of the course of the open note.
    public func openAdjacentLecture(_ step: Int) {
        guard let course = currentCourse else { return }
        let notes = courses.notes(of: course).filter { $0.date != nil }.sorted { $0.date! < $1.date! }
        let today = env.clock.today
        let index: Int
        if let id = editor?.noteID, let i = notes.firstIndex(where: { $0.id == id }) {
            index = i + step
        } else {
            index = step > 0 ? (notes.firstIndex { $0.date! >= today } ?? notes.count) : (notes.lastIndex { $0.date! < today } ?? -1)
        }
        guard notes.indices.contains(index) else { show(step > 0 ? "No later lecture" : "No earlier lecture", icon: "info"); return }
        open(note: notes[index])
    }
}

/// The note page's editor, if the active tab is one.
struct ActiveEditor {
    weak var model: NoteEditorModel?
    weak var handle: EditorHandle?
}

// MARK: Import


extension Workspace {
    /// File › Import › Markdown files…: each chosen `.md` / `.txt` file becomes a note of the current
    /// course (else the first one), titled after the file; its text is kept as it is.
    public func importMarkdownFiles() {
        guard let course = currentCourse ?? courses.cards.first?.id else {
            show("Add a course first, then import into it", icon: "error", error: true)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.message = "Choose Markdown files to import into \(courses.course(id: course)?.name ?? course)"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        perform("Import") {
            var imported = 0
            for url in urls {
                let text = try String(contentsOf: url, encoding: .utf8)
                let title = url.deletingPathExtension().lastPathComponent
                _ = try await self.env.notes.create(course: course, title: title, kind: .note, text: text, actor: .user,
                                                    baseVersion: nil, dryRun: false, idempotencyKey: nil)
                imported += 1
            }
            await self.refreshAfterWrite()
            self.show("Imported \(imported) \(imported == 1 ? "note" : "notes")", icon: "upload_file")
        }
    }
}
