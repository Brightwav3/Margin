import AppKit
import MarginCore
import SwiftUI

/// Note editor page (3a): top bar, properties, the Markdown text and the status bar.
struct NoteEditorView: View {
    @Bindable var model: NoteEditorModel
    @Environment(Workspace.self) private var workspace
    @State private var handle = EditorHandle()
    @State private var popup = EditorPopupState()
    @State private var showBacklinks = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let error = model.error { ErrorBanner(text: error) }
                        // `Note.text` is the body; the frontmatter lives in this panel in every mode.
                        if model.showsProperties, !model.properties.isEmpty || model.noteID != nil {
                            PropertiesPanel(model: model)
                        }
                        MarkdownTextView(text: model.text, revision: model.revision &+ model.styleRevision &* 100_000, mode: model.mode,
                                         onEdit: { model.edit($0) }, events: events, handle: handle)
                        if showBacklinks { BacklinksInDocument(model: model) }
                    }
                    .frame(maxWidth: model.readableLineLength ? 700 : .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 18)
                    .padding(.bottom, 60)
                    .frame(maxWidth: .infinity)
                }
                StatusBar(model: model) { workspace.open(.today) }
                if model.mode != .reading {
                    EditorTips()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 24).padding(.bottom, 44)
                }
            }
            .overlay { EditorPopups(state: popup, model: model, handle: handle) }
        }
        .task {
            await model.load()
            if let course = model.courseID {
                let courseModel = workspace.courseModel(course)
                if !courseModel.isLoaded { await courseModel.load() }
            }
            if let reveal = workspace.reveal, reveal.note == model.noteID {
                workspace.reveal = nil
                try? await Task.sleep(for: .milliseconds(150))
                handle.reveal(line: reveal.line)
            }
        }
        .task { await model.observeExternalChanges() }
        .onAppear { workspace.setActiveEditor(model, handle: handle) }
        .onDisappear {
            if workspace.editor === model { workspace.setActiveEditor(nil, handle: nil) }
            Task { await model.flush() }
        }
        .onChange(of: workspace.reveal?.line) { _, line in
            if let line, workspace.reveal?.note == model.noteID { workspace.reveal = nil; handle.reveal(line: line) }
        }
        .background {
            Button("Toggle reading view") { model.toggleReading() }
                .keyboardShortcut("e", modifiers: .command)
                .opacity(0).allowsHitTesting(false)
        }
    }

    private var events: EditorEvents {
        var e = EditorEvents()
        e.onOpenLink = { target in workspace.openLink(target, from: model.courseID) }
        e.onLinkQuery = { q, rect in popup.link(q, at: rect, workspace: workspace, course: model.courseID, note: model.noteID) }
        e.onSlashQuery = { q, rect in popup.slash(q, at: rect, clock: workspace.env.clock) }
        e.onHoverLink = { target, rect in popup.hover(target, at: rect, workspace: workspace) }
        e.onPopupKey = { key in popup.key(key, handle: handle, workspace: workspace) }
        e.onSelection = { rect in popup.selectionRect = model.mode == .reading ? nil : rect }
        e.onContextMenu = { ctx in EditorMenus.menu(for: ctx, model: model, handle: handle, workspace: workspace) }
        return e
    }

    // MARK: Top bar (52 px: edited · breadcrumb · icons)

    private var topBar: some View {
        HStack(spacing: 16) {
            Text(model.editedLine)
                .marginFont(MarginTextSize.sm)
                .foregroundStyle(MarginColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            breadcrumb
            HStack(spacing: 16) {
                ChromeButton(icon: "text_fields", help: "Text style") { popup.showStyleMenu.toggle() }
                    .popover(isPresented: $popup.showStyleMenu, arrowEdge: .bottom) {
                        TextStyleMenu(handle: handle) { popup.showStyleMenu = false }
                    }
                ChromeButton(icon: "link", help: "Copy link to this note") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("[[\(model.title)]]", forType: .string)
                    workspace.show("Link copied")
                }
                ChromeButton(icon: model.mode == .reading ? "menu_book" : "edit",
                             help: model.mode == .reading ? "Reading view · click to edit (⌘E)" : "Editing · click for reading view (⌘E)") {
                    model.toggleReading()
                }
                NoteMenuButton(model: model, handle: handle, showBacklinks: $showBacklinks)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            if let course = model.courseID.flatMap({ workspace.courses.course(id: $0) }) {
                Circle().fill(Color(hexString: course.style.dot)).frame(width: 7, height: 7)
                Button(course.name) { workspace.open(course: course) }
                    .buttonStyle(.plain)
                    .foregroundStyle(MarginColor.textSecondary)
                Text("/").foregroundStyle(MarginColor.textDisabled)
            }
            Text(CourseDetailModel.split(model.summary ?? NoteSummary(id: "", title: model.title)).0 == "Note"
                 ? model.title : CourseDetailModel.split(model.summary ?? NoteSummary(id: "", title: model.title)).0)
                .foregroundStyle(MarginColor.ink)
        }
        .marginFont(MarginTextSize.base)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Error or merge notice above the text.
struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Icon("error", size: 16, color: MarginColor.warningText)
            Text(text).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.warningText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarginColor.warningSoft, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        .padding(.bottom, 12)
    }
}

/// Status bar (bottom right): backlinks, properties, words, open tasks → Today (M6-08).
private struct StatusBar: View {
    let model: NoteEditorModel
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(count(model.stats.backlinks, "backlink"))
            Text(count(model.properties.count, "property", "properties"))
            Text(count(model.stats.words, "word"))
            if model.stats.openTasks > 0 {
                Button("\(count(model.stats.openTasks, "open task")) → Today", action: onToday).buttonStyle(.plain)
            }
        }
        .marginFont(MarginTextSize.sm)
        .foregroundStyle(MarginColor.textSecondary)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(MarginColor.inspector)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 10).stroke(MarginColor.borderSubtle)
                .padding(.trailing, -1).padding(.bottom, -1)
        }
    }

    private func count(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : (many ?? one + "s"))"
    }
}

/// „Backlinks in document“: linked mentions under the text.
private struct BacklinksInDocument: View {
    let model: NoteEditorModel
    @Environment(Workspace.self) private var workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarginDivider().padding(.vertical, 12)
            Text("Linked mentions · \(model.backlinks.count)").marginFont(MarginTextSize.sm, .semibold)
                .foregroundStyle(MarginColor.textSecondary)
            ForEach(model.backlinks) { link in
                Button { workspace.open(.note(link.sourceNoteID), title: link.sourceTitle) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.sourceTitle).marginFont(MarginTextSize.base, .semibold).foregroundStyle(MarginColor.accentText)
                        Text(link.context).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
