import AppKit
import MarginCore
import SwiftUI

/// `…` menu of a note (3a, M6-07): the 25 items of the mockup. Items whose feature lands in a
/// later milestone are disabled and say why.
struct NoteMenuButton: View {
    let model: NoteEditorModel
    let handle: EditorHandle
    @Binding var showBacklinks: Bool
    @Environment(Workspace.self) private var workspace
    @State private var open = false

    var body: some View {
        ChromeButton(icon: "more_horiz", help: "More") { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) { items }
                        .padding(5)
                }
                .frame(width: 250)
                .frame(maxHeight: 640)
            }
    }

    private var note: NoteSummary? { model.summary }

    @ViewBuilder
    private var items: some View {
        row("Backlinks in document", checked: showBacklinks) { showBacklinks.toggle() }
        sep
        row("Reading view", checked: model.mode == .reading, shortcut: "⌘E") { model.toggleReading() }
        row("Source mode", checked: model.mode == .source) { model.setMode(model.mode == .source ? .live : .source) }
        row("Readable line length", checked: model.readableLineLength) { model.readableLineLength.toggle() }
        sep
        later("Split right"); later("Split down"); later("Open in new window")
        sep
        row("Rename…", disabled: true, help: "Edit the title line (# …) to rename the note")
        row("Move file to…", disabled: note == nil) { if let note { workspace.dialog = .moveNote(note) } }
        later("Bookmark…")
        row("Add file property", disabled: model.isDraft) {
            Task { await model.setProperty("new property", .string("")) }
        }
        row("Export to PDF…", disabled: note == nil) { if let note { workspace.dialog = .share(note) } }
        sep
        row("Find…", shortcut: "⌘F") { handle.focus(); handle.textView?.performTextFinderAction(findItem(.showFindInterface)) }
        row("Replace…", shortcut: "⌥⌘F", disabled: model.mode == .reading) {
            handle.focus(); handle.textView?.performTextFinderAction(findItem(.showReplaceInterface))
        }
        sep
        row("Copy path", disabled: note == nil) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note?.id ?? "", forType: .string)
            workspace.show("Path copied")
        }
        sep
        row("Open version history", disabled: model.noteID == nil) { if let id = model.noteID { workspace.dialog = .history(id) } }
        row("Open linked view") { workspace.open(.graph) }
        sep
        row("Reveal in Finder", disabled: true, help: "Needs the note's file path from the backend contract")
        row("Reveal file in navigation") { workspace.shell.sidebarPage = .notes; workspace.shell.sidebarCollapsed = false }
        sep
        row("Ask agent about this note", disabled: true, help: "The in-app agent comes in a later version")
        sep
        row("Delete file", destructive: true, disabled: note == nil) { if let note { workspace.dialog = .deleteNote(note) } }
    }

    private func findItem(_ action: NSTextFinder.Action) -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = action.rawValue
        return item
    }

    private var sep: some View { MarginDivider(color: Color(hex: 0xEDEEF1)).padding(.horizontal, 8).padding(.vertical, 4) }

    private func later(_ title: String) -> some View {
        row(title, disabled: true, help: "Split views and extra windows come in a later version")
    }

    private func row(_ title: String, checked: Bool = false, shortcut: String = "", destructive: Bool = false,
                     disabled: Bool = false, help: String? = nil, action: @escaping () -> Void = {}) -> some View {
        MenuRow(title: title, icon: checked ? nil : "", shortcut: shortcut, checked: checked, destructive: destructive,
                disabled: disabled, help: help) {
            action()
            open = false
        }
    }
}

/// Right-click menus inside the editor (Margin Menus 1c–1i).
@MainActor
enum EditorMenus {
    static func menu(for ctx: EditorContext, model: NoteEditorModel, handle: EditorHandle, workspace: Workspace) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, key: String = "", enabled: Bool = true, _ action: @escaping @MainActor () -> Void) {
            let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
            item.isEnabled = enabled
            menu.addItem(item)
        }
        switch ctx.kind {
        case .selection(let text):
            add("Cut", key: "x") { handle.textView?.cut(nil) }
            add("Copy", key: "c") { handle.textView?.copy(nil) }
            add("Paste", key: "v") { handle.textView?.paste(nil) }
            menu.addItem(.separator())
            add("Bold") { handle.wrapSelection("**", "**") }
            add("Italic") { handle.wrapSelection("*", "*") }
            add("Highlight") { handle.wrapSelection("==", "==") }
            add("Make link") { handle.wrapSelection("[[", "]]") }
            add("Make task") { handle.wrapSelection("- [ ] ", "") }
            menu.addItem(.separator())
            add("Search for “\(text.prefix(24))”") { workspace.open(.search(text)) }
        case .link(let target):
            add("Open link") { workspace.openLink(target, from: model.courseID) }
            add("Open in new tab") { workspace.openLink(target, from: model.courseID) }
            add("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[[\(target)]]", forType: .string)
            }
            menu.addItem(.separator())
            add("Show backlinks") { workspace.shell.inspectorOpen = true; workspace.shell.inspectorTab = .backlinks }
        case .task(let line):
            add("Toggle done") { toggleTask(line: line, handle: handle) }
            add("Due today") { setDue(line: line, "today", handle: handle) }
            add("Due tomorrow") { setDue(line: line, "tomorrow", handle: handle) }
            add("Due before the next lecture") { setDue(line: line, "before-lecture", handle: handle) }
            add("Open in Today") { workspace.open(.today) }
        case .heading(let title):
            add("Copy link to heading") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[[\(model.title)#\(title)]]", forType: .string)
            }
            add("Show outline") { workspace.shell.inspectorOpen = true; workspace.shell.inspectorTab = .outline }
        case .image, .table, .plain:
            add("Paste", key: "v") { handle.textView?.paste(nil) }
            add("Select all", key: "a") { handle.textView?.selectAll(nil) }
            menu.addItem(.separator())
            add("Insert task") { handle.insert("- [ ] ") }
            add("Insert link") { handle.insert("[[") }
            add("Insert today's date") { handle.insert(workspace.env.clock.today.iso) }
        }
        return menu
    }

    /// `- [ ]` ↔ `- [x]` on a 0-based line, as an undoable edit.
    static func toggleTask(line: Int, handle: EditorHandle) {
        guard let tv = handle.textView else { return }
        let text = tv.string as NSString
        guard let range = lineRange(line, in: text) else { return }
        let content = text.substring(with: range)
        guard let open = content.range(of: "[") else { return }
        let offset = content.utf16.distance(from: content.utf16.startIndex, to: open.lowerBound.samePosition(in: content.utf16)!)
        let at = NSRange(location: range.location + offset + 1, length: 1)
        tv.replace(at, with: text.substring(with: at) == " " ? "x" : " ")
    }

    /// Sets the `@due` token of a task line (spec 05 §3): replaces the last `@word`, else appends it
    /// before the block id (`^t-4f2a`).
    static func setDue(line: Int, _ token: String, handle: EditorHandle) {
        guard let tv = handle.textView else { return }
        let text = tv.string as NSString
        guard var range = lineRange(line, in: text) else { return }
        if range.length > 0, text.character(at: NSMaxRange(range) - 1) == 0x0A { range.length -= 1 }
        var words = text.substring(with: range).components(separatedBy: " ")
        var blockID: String?
        if let last = words.last, last.hasPrefix("^") { blockID = words.removeLast() }
        if let i = words.lastIndex(where: { $0.hasPrefix("@") && $0.count > 1 }) {
            words[i] = "@\(token)"
        } else if let i = words.lastIndex(of: "@"), i + 1 < words.count {
            words.removeSubrange(i...(i + 1)); words.append("@\(token)")
        } else {
            words.append("@\(token)")
        }
        if let blockID { words.append(blockID) }
        tv.replace(range, with: words.joined(separator: " "))
    }

    static func lineRange(_ line: Int, in text: NSString) -> NSRange? {
        var location = 0
        for _ in 0..<line {
            guard location < text.length else { return nil }
            location = NSMaxRange(text.lineRange(for: NSRange(location: location, length: 0)))
        }
        guard location <= text.length else { return nil }
        return text.lineRange(for: NSRange(location: location, length: 0))
    }
}

/// `NSMenuItem` running a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, keyEquivalent: String = "", action: @escaping @MainActor () -> Void) {
        self.run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { run() }
}
