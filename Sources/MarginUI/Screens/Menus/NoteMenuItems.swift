import AppKit
import MarginCore
import SwiftUI

/// 1a: the menu of a note in the sidebar, the course gallery and search results.
struct NoteMenuItems: View {
    let note: NoteSummary
    @Environment(Workspace.self) private var workspace

    var body: some View {
        MenuItem("Open in new tab", "open_in_new") { workspace.open(.note(note.id), title: note.title, newTab: true) }
            .keyboardShortcut(.return, modifiers: .command)
        MenuItem("Open to the right", "vertical_split") {}.disabled(true)
        Divider()
        MenuItem("Rename…", "edit") { workspace.dialog = .renameNote(note) }
        MenuItem("Duplicate", "content_copy") { workspace.duplicate(note) }
        MenuItem("Move to…", "drive_file_move") { workspace.dialog = .moveNote(note) }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        MenuItem("Copy link", "link") { workspace.copyLink(to: note) }
        Divider()
        MenuItem("Add to revision", "timer") { workspace.addToRevision(note) }
        MenuItem("Reveal in Finder", "folder_open") { workspace.revealInFinder(note) }
            .disabled(workspace.vaultURL == nil)
        Divider()
        MenuItem("Delete note", "delete", role: .destructive) { workspace.requestDelete(note) }
    }
}

extension Workspace {
    /// A copy next to the note, named „… copy“, opened in the active tab.
    func duplicate(_ note: NoteSummary) {
        guard let course = note.courseID else { return }
        perform("Duplicate note") {
            let text = try await self.env.notes.open(id: note.id).text
            var title = note.title + " copy"
            let existing = Set(try await self.env.notes.notes(course: course).map(\.title))
            var n = 2
            while existing.contains(title) { title = note.title + " copy \(n)"; n += 1 }
            let cs = try await self.env.notes.create(course: course, title: title, kind: note.kind, text: text, actor: .user,
                                                    baseVersion: nil, dryRun: false, idempotencyKey: nil)
            await self.refreshAfterWrite()
            if let id = cs.entries.first?.noteID { self.open(.note(id), title: title) }
            self.show("Duplicated as “\(title)”", icon: "content_copy")
        }
    }

    /// `[[Title]]` on the clipboard.
    func copyLink(to note: NoteSummary) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[[\(note.title)]]", forType: .string)
        show("Copied [[\(note.title)]]", icon: "link")
    }

    /// Adds the `revision` tag (Revision page, flashcards later).
    func addToRevision(_ note: NoteSummary) {
        perform("Add to revision") {
            let props = try await self.env.analysis.properties(id: note.id)
            var tags: [FrontmatterValue] = []
            if case .list(let old)? = props.first(where: { $0.key == "tags" })?.value { tags = old }
            guard !tags.contains(.string("revision")) else { self.show("Already in revision"); return }
            tags.append(.string("revision"))
            _ = try await self.env.properties.set(key: "tags", value: .list(tags), on: note.id, actor: .user,
                                                  baseVersion: nil, dryRun: false, idempotencyKey: nil)
            self.show("Added to revision", icon: "sell")
        }
    }

    /// Shows the note's file in Finder.
    func revealInFinder(_ note: NoteSummary) {
        guard let vault = vaultURL else { return }
        perform("Reveal in Finder") {
            let path = try await self.env.notes.filePath(id: note.id)
            NSWorkspace.shared.activateFileViewerSelecting([vault.appendingPathComponent(path)])
        }
    }

    /// The vault-relative path of a note on the clipboard.
    func copyFilePath(_ note: NoteSummary) {
        perform("Copy file path") {
            let path = try await self.env.notes.filePath(id: note.id)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            self.show("Copied \(path)", icon: "content_copy")
        }
    }
}

/// Rename a note: file, title and links in other notes follow.
struct RenameNoteDialog: View {
    let note: NoteSummary
    @Environment(Workspace.self) private var workspace
    @State private var title = ""

    var body: some View {
        DialogCard(title: "Rename note", width: 440) {
            MarginField(placeholder: note.title, text: $title)
            Text("The file is renamed too, and links to it in other notes follow.")
                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Rename", kind: .primary) {
                let new = title.trimmingCharacters(in: .whitespaces)
                workspace.perform("Rename note") {
                    _ = try await workspace.env.notes.rename(id: note.id, to: new, actor: .user, baseVersion: nil,
                                                             dryRun: false, idempotencyKey: nil)
                    workspace.dialog = nil
                    await workspace.reloadEditor(note.id)
                    workspace.refreshTabTitles()
                    workspace.show("Renamed to “\(new)”", icon: "edit")
                }
            }
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction)
        }
        .onAppear { title = note.title }
    }
}
