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
            // The copy's own title: the first `# heading` follows the new name.
            var lines = text.components(separatedBy: "\n")
            if let i = lines.firstIndex(where: { $0.hasPrefix("# ") }) { lines[i] = "# " + title }
            let copy = lines.joined(separator: "\n")
            let cs = try await self.env.notes.create(course: course, title: title, kind: note.kind, text: copy, actor: .user,
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


/// 1m Rename everywhere… / Delete tag…: every note with the tag is rewritten (one undoable save each).
struct TagDialog: View {
    let tag: String
    let deleting: Bool
    @Environment(Workspace.self) private var workspace
    @State private var name = ""
    @State private var count: Int?

    var body: some View {
        DialogCard(title: deleting ? "Delete \(tag)?" : "Rename \(tag)", icon: "sell", width: 440) {
            if !deleting {
                MarginField(placeholder: tag, text: $name)
            }
            Text(count.map { "\($0) \($0 == 1 ? "note uses" : "notes use") \(tag). " } ?? "" +
                 (deleting ? "The tag is removed from them; the notes stay." : "Each of them is updated."))
                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton(deleting ? "Delete tag" : "Rename", kind: .primary) { run() }
                .disabled(!deleting && TagEditing.normalized(name) == nil).keyboardShortcut(.defaultAction)
        }
        .task {
            name = tag
            count = await TagEditing.notes(with: tag, env: workspace.env).count
        }
    }

    private func run() {
        let replacement = deleting ? nil : TagEditing.normalized(name)
        workspace.perform(deleting ? "Delete tag" : "Rename tag") {
            let changed = try await TagEditing.rewrite(tag, to: replacement, env: workspace.env)
            workspace.dialog = nil
            for id in changed { await workspace.reloadEditor(id) }
            await workspace.refreshAfterWrite()
            workspace.show(deleting ? "Removed \(tag) from \(changed.count) notes" : "Renamed \(tag) in \(changed.count) notes", icon: "sell")
        }
    }
}

/// Finding and rewriting `#tag` in note texts (outside code).
enum TagEditing {
    /// `#name` from what the user typed (with or without `#`); nil when not a valid tag.
    static func normalized(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let name = t.hasPrefix("#") ? String(t.dropFirst()) : t
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || "_-/".contains($0) }),
              !name.allSatisfy(\.isNumber) else { return nil }
        return "#" + name
    }

    static func regex(_ tag: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: "(?<=^|\\s)" + NSRegularExpression.escapedPattern(for: tag) + "(?![\\p{L}\\p{N}_/-])",
                                 options: [.anchorsMatchLines])
    }

    static func replace(_ tag: String, with new: String?, in text: String) -> String {
        guard let regex = regex(tag) else { return text }
        let out = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                                 withTemplate: NSRegularExpression.escapedTemplate(for: new ?? ""))
        return new == nil ? out.replacingOccurrences(of: "  ", with: " ") : out
    }

    static func notes(with tag: String, env: AppEnvironment) async -> [NoteID] {
        guard let regex = regex(tag) else { return [] }
        var hits: [NoteID] = []
        for summary in (try? await env.notes.notes(course: nil)) ?? [] {
            guard let note = try? await env.notes.open(id: summary.id) else { continue }
            if regex.firstMatch(in: note.text, range: NSRange(location: 0, length: (note.text as NSString).length)) != nil { hits.append(note.id) }
        }
        return hits
    }

    /// Rewrites every note with `tag`; returns the notes changed.
    static func rewrite(_ tag: String, to new: String?, env: AppEnvironment) async throws -> [NoteID] {
        var changed: [NoteID] = []
        for id in await notes(with: tag, env: env) {
            let note = try await env.notes.open(id: id)
            let text = replace(tag, with: new, in: note.text)
            guard text != note.text else { continue }
            _ = try await env.notes.save(id: id, text: text, actor: .user, baseVersion: note.version, dryRun: false, idempotencyKey: nil)
            changed.append(id)
        }
        return changed
    }
}
