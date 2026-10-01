import AppKit
import MarginCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: Selection (1r)

extension Workspace {
    /// A click in a note list: plain opens the note, ⌘ adds or removes it, ⇧ selects the range from
    /// the last clicked note. `order` is the list as shown.
    func click(note: NoteSummary, in order: [NoteSummary], modifiers: NSEvent.ModifierFlags, open: () -> Void) {
        if modifiers.contains(.command) {
            if noteSelection.isEmpty, let current = currentNote, current.id != note.id, order.contains(where: { $0.id == current.id }) {
                noteSelection = [current]
            }
            if let i = noteSelection.firstIndex(where: { $0.id == note.id }) { noteSelection.remove(at: i) }
            else { noteSelection.append(note) }
            selectionAnchor = note.id
        } else if modifiers.contains(.shift), let anchor = selectionAnchor ?? currentNote?.id,
                  let a = order.firstIndex(where: { $0.id == anchor }), let b = order.firstIndex(where: { $0.id == note.id }) {
            noteSelection = Array(order[min(a, b)...max(a, b)])
        } else {
            noteSelection = []
            selectionAnchor = note.id
            open()
        }
    }

    func isSelected(note id: NoteID) -> Bool { noteSelection.contains { $0.id == id } }

    func openInTabs(_ notes: [NoteSummary]) {
        for note in notes { open(.note(note.id), title: note.title, newTab: true) }
        noteSelection = []
    }

    /// The notes one after another in one Markdown text, each under its title.
    static func combined(_ notes: [(title: String, text: String)]) -> String {
        notes.map { note in
            let body = Self.withoutTitle(note.text, title: note.title)
            return "# \(note.title)\n\n" + body
        }.joined(separator: "\n\n")
    }

    /// The body without its first `# Title` line (the merged note gets `## Title` instead).
    static func withoutTitle(_ text: String, title: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].hasPrefix("# ") {
            lines.remove(at: first)
            while let line = lines.first, line.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// The first note keeps its text; the others follow as `## Title` sections and go to the Trash.
    func merge(_ notes: [NoteSummary]) {
        guard let target = notes.first, notes.count > 1 else { return }
        perform("Merge notes") {
            let first = try await self.env.notes.open(id: target.id)
            var text = first.text.trimmingCharacters(in: .newlines)
            for other in notes.dropFirst() {
                let note = try await self.env.notes.open(id: other.id)
                text += "\n\n## \(other.title)\n\n" + Self.withoutTitle(note.text, title: other.title)
            }
            _ = try await self.env.notes.save(id: target.id, text: text + "\n", actor: .user, baseVersion: first.version,
                                              dryRun: false, idempotencyKey: nil)
            for other in notes.dropFirst() {
                _ = try await self.env.notes.delete(id: other.id, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
                self.closeTabs(of: .note(other.id))
            }
            self.dialog = nil
            self.noteSelection = []
            self.show("Merged \(notes.count) notes into “\(target.title)”", icon: "merge")
            await self.refreshAfterWrite()
            self.open(.note(target.id), title: target.title)
        }
    }

    func addTag(_ tag: String, to notes: [NoteSummary]) {
        guard let name = TagEditing.normalized(tag), !name.isEmpty else { return }
        perform("Add tag") {
            for note in notes {
                let props = try await self.env.analysis.properties(id: note.id)
                var tags: [FrontmatterValue] = []
                if case .list(let old)? = props.first(where: { $0.key == "tags" })?.value { tags = old }
                guard !tags.contains(.string(name)) else { continue }
                tags.append(.string(name))
                _ = try await self.env.properties.set(key: "tags", value: .list(tags), on: note.id, actor: .user,
                                                      baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
            self.dialog = nil
            self.noteSelection = []
            self.show("Tagged \(notes.count) notes #\(name)", icon: "sell")
            await self.refreshAfterWrite()
        }
    }

    private func texts(_ notes: [NoteSummary]) async throws -> [(title: String, text: String)] {
        var result: [(String, String)] = []
        for note in notes { result.append((note.title, try await env.notes.open(id: note.id).text)) }
        return result
    }

    func copyAsMarkdown(_ notes: [NoteSummary]) {
        perform("Copy notes") {
            let text = Self.combined(try await self.texts(notes))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            self.show("Copied \(notes.count) notes as Markdown")
        }
    }

    func exportMarkdown(_ notes: [NoteSummary]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(notes.first?.title ?? "Notes") a další.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform("Export notes") {
            let text = Self.combined(try await self.texts(notes))
            try Data(text.utf8).write(to: url, options: .atomic)
            self.show("Exported \(notes.count) notes")
        }
    }

    func requestDelete(_ notes: [NoteSummary]) {
        if confirmBeforeDeleting { dialog = .deleteNotes(notes) } else { trash(notes) }
    }

    func trash(_ notes: [NoteSummary]) {
        perform("Delete notes") {
            for note in notes {
                _ = try await self.env.notes.delete(id: note.id, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
                self.closeTabs(of: .note(note.id))
            }
            self.dialog = nil
            self.noteSelection = []
            self.show("Moved \(notes.count) notes to the Trash", icon: "delete")
            await self.refreshAfterWrite()
        }
    }
}

/// 1r Menu of several selected notes.
struct MultiNoteMenuItems: View {
    let notes: [NoteSummary]
    @Environment(Workspace.self) private var workspace

    var body: some View {
        Section("\(notes.count) notes selected") {
            MenuItem("Open in tabs", "tab") { workspace.openInTabs(notes) }
            MenuItem("Merge into one note", "merge") { workspace.dialog = .mergeNotes(notes) }
            MenuItem("Move to…", "drive_file_move") { workspace.dialog = .moveNotes(notes) }
            MenuItem("Add tag…", "sell") { workspace.dialog = .tagNotes(notes) }
            Menu {
                Button("Copy as Markdown") { workspace.copyAsMarkdown(notes) }
                Button("Save as one Markdown file…") { workspace.exportMarkdown(notes) }
            } label: { Label { Text("Export") } icon: { MenuIcons.image("ios_share") } }
        }
        Divider()
        MenuItem("Delete \(notes.count) notes", "delete", role: .destructive) { workspace.requestDelete(notes) }
    }
}

// MARK: Dialogs

struct DeleteNotesDialog: View {
    let notes: [NoteSummary]
    @Environment(Workspace.self) private var workspace

    var body: some View {
        DialogCard(title: "Delete \(notes.count) notes?", icon: "delete", width: 460) {
            Text(notes.map(\.title).joined(separator: ", ")).marginFont(MarginTextSize.base, .medium).lineLimit(3)
            Text("The files go to the Trash; you can restore them from there. Links to them stay as unresolved links.")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }.keyboardShortcut(.cancelAction)
            Button { workspace.trash(notes) } label: {
                Text("Delete \(notes.count) notes").marginFont(MarginTextSize.base, .medium).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(MarginColor.due, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
            }
            .buttonStyle(.plain).keyboardShortcut(.defaultAction)
        }
    }
}

struct MergeNotesDialog: View {
    let notes: [NoteSummary]
    @Environment(Workspace.self) private var workspace

    var body: some View {
        DialogCard(title: "Merge \(notes.count) notes", icon: "merge", width: 480) {
            Text("“\(notes[0].title)” keeps its text; the others follow it as sections and go to the Trash.")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { i, note in
                    HStack(spacing: 8) {
                        Icon(i == 0 ? "description" : "subdirectory_arrow_right", size: 16, color: MarginColor.textTertiary)
                        Text(note.title).marginFont(MarginTextSize.base, i == 0 ? .semibold : .regular)
                    }
                }
            }
            Text("Links to the merged notes stay as unresolved links.")
                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }.keyboardShortcut(.cancelAction)
            MarginButton("Merge", kind: .primary) { workspace.merge(notes) }.keyboardShortcut(.defaultAction)
        }
    }
}

struct AddTagDialog: View {
    let notes: [NoteSummary]
    @Environment(Workspace.self) private var workspace
    @State private var tag = ""

    var body: some View {
        DialogCard(title: "Add tag to \(notes.count) notes", icon: "sell", width: 420) {
            MarginField(placeholder: "exam", text: $tag)
                .onSubmit { workspace.addTag(tag, to: notes) }
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }.keyboardShortcut(.cancelAction)
            MarginButton("Add tag", kind: .primary) { workspace.addTag(tag, to: notes) }
                .disabled(TagEditing.normalized(tag)?.isEmpty ?? true)
                .keyboardShortcut(.defaultAction)
        }
    }
}
