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
        row("Open linked view") { if let id = model.noteID { workspace.openLocalGraph(id) } else { workspace.open(.graph) } }
        sep
        row("Reveal in Finder", disabled: true, help: "Needs the note's file path from the backend contract")
        row("Reveal file in navigation") { workspace.shell.sidebarPage = .notes; workspace.shell.sidebarCollapsed = false }
        sep
        row("Ask agent about this note", disabled: true, help: "The in-app agent comes in a later version")
        sep
        row("Delete file", destructive: true, disabled: note == nil) { if let note { workspace.requestDelete(note) } }
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
        let editable = model.mode != .reading
        @discardableResult
        func add(_ title: String, _ icon: String? = nil, key: String = "", mods: NSEvent.ModifierFlags = .command,
                 enabled: Bool = true, to target: NSMenu? = nil, _ action: @escaping @MainActor () -> Void = {}) -> NSMenuItem {
            let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
            item.keyEquivalentModifierMask = mods
            item.isEnabled = enabled
            if let icon { item.image = MenuIcons.nsImage(icon) }
            (target ?? menu).addItem(item)
            return item
        }
        func header(_ title: String) { menu.addItem(NSMenuItem.sectionHeader(title: title)) }
        func sep(_ target: NSMenu? = nil) { (target ?? menu).addItem(.separator()) }
        func submenu(_ title: String, _ icon: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.image = MenuIcons.nsImage(icon)
            let sub = NSMenu(title: title)
            build(sub)
            item.submenu = sub
            menu.addItem(item)
        }
        let tv = handle.textView

        switch ctx.kind {
        case .selection(let text):
            // 1d
            add("Cut", "content_cut", key: "x", enabled: editable) { tv?.cut(nil) }
            add("Copy", "content_copy", key: "c") { tv?.copy(nil) }
            add("Paste", "content_paste", key: "v", enabled: editable) { tv?.paste(nil) }
            sep()
            submenu("Format", "format_bold") { sub in
                add("Bold", "format_bold", key: "b", enabled: editable, to: sub) { handle.toggle(.bold) }
                add("Italic", "format_italic", key: "i", enabled: editable, to: sub) { handle.toggle(.italic) }
                add("Strikethrough", "strikethrough_s", key: "x", mods: [.command, .shift], enabled: editable, to: sub) { handle.toggle(.strike) }
                add("Highlight", "ink_highlighter", key: "h", mods: [.command, .shift], enabled: editable, to: sub) { handle.toggle(.highlight) }
                add("Inline code", "code", key: "`", enabled: editable, to: sub) { handle.toggle(.code) }
                sep(sub)
                add("Clear formatting", "format_clear", enabled: editable, to: sub) { handle.clearFormatting() }
            }
            add("Link to note…", "add_link", key: "k", enabled: editable) { handle.wrapSelection("[[", "]]") }
            add("Extract to new note", "call_split", enabled: editable && model.courseID != nil) {
                extract(text, title: firstLine(text), handle: handle, model: model, workspace: workspace)
            }
            add("Search for “\(text.prefix(24))”", "search") { workspace.open(.search(text)) }
            add("Make flashcard", "style", enabled: false)
            sep()
            header("Agent")
            add("Explain", "auto_awesome", enabled: false)
            add("Simplify", "short_text", enabled: false)
            add("Quiz me on this", "quiz", enabled: false)

        case .link(let target):
            // 1e
            add("Open link", "north_east") { workspace.openLink(target, from: model.courseID) }
            add("Open in new tab", "open_in_new", key: "\r") { workspace.openLink(target, from: model.courseID, newTab: true) }
            add("Open to the right", "vertical_split", enabled: false)
            add("Show backlinks", "call_received") { workspace.shell.inspectorOpen = true; workspace.shell.inspectorTab = .backlinks }
            sep()
            add("Edit display text", "edit", enabled: editable) { editLink(at: ctx.location, handle: handle, part: .alias) }
            add("Change target…", "swap_horiz", enabled: editable) { editLink(at: ctx.location, handle: handle, part: .target) }
            add("Copy link", "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[[\(target)]]", forType: .string)
            }
            sep()
            add("Unlink", "link_off", enabled: editable) { unlink(at: ctx.location, handle: handle) }

        case .task(let line):
            // 1f
            header("Task")
            add("Mark done", "check_circle", key: "\r", enabled: editable) { toggleTask(line: line, handle: handle) }
            submenu("Due date", "event") { sub in
                add("Today", "light_mode", enabled: editable, to: sub) { setDue(line: line, "today", handle: handle) }
                add("Tomorrow", "calendar_today", enabled: editable, to: sub) { setDue(line: line, "tomorrow", handle: handle) }
                add("Next week", "date_range", enabled: editable, to: sub) { setDue(line: line, "next-week", handle: handle) }
                add("Before the exam", "quiz", enabled: editable, to: sub) { setDue(line: line, "before-exam", handle: handle) }
            }
            add("Do today", "light_mode", enabled: editable) { setDue(line: line, "today", handle: handle) }
            let next = add("Before next lecture", "school", enabled: editable) { setDue(line: line, "before-lecture", handle: handle) }
            next.toolTip = "Follows the course: if the lecture moves, the task moves with it."
            sep()
            add("Convert to note", "description", enabled: editable && model.courseID != nil) {
                convertTask(line: line, handle: handle, model: model, workspace: workspace)
            }
            add("Open in Today", "light_mode") { workspace.open(.today) }
            sep()
            add("Delete task", "delete", enabled: editable) { deleteLine(line, handle: handle) }

        case .heading(let title):
            // 1g
            submenu("Turn into", "text_fields") { sub in
                add("Heading 1", key: "1", mods: [.command, .option], enabled: editable, to: sub) { handle.setBlock(.heading1) }
                add("Heading 2", key: "2", mods: [.command, .option], enabled: editable, to: sub) { handle.setBlock(.heading2) }
                add("Heading 3", key: "3", mods: [.command, .option], enabled: editable, to: sub) { handle.setBlock(.heading3) }
                add("Paragraph", key: "0", mods: [.command, .option], enabled: editable, to: sub) { handle.setBlock(.paragraph) }
            }
            add("Copy link to heading", "tag") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[[\(model.title)#\(title)]]", forType: .string)
            }
            add("Move section up", "arrow_upward", key: String(UnicodeScalar(NSUpArrowFunctionKey)!), mods: .option, enabled: editable) {
                moveSection(at: ctx.location, up: true, handle: handle)
            }
            add("Move section down", "arrow_downward", key: String(UnicodeScalar(NSDownArrowFunctionKey)!), mods: .option, enabled: editable) {
                moveSection(at: ctx.location, up: false, handle: handle)
            }
            add("Extract to new note", "call_split", enabled: editable && model.courseID != nil) {
                extractSection(at: ctx.location, title: title, handle: handle, model: model, workspace: workspace)
            }
            add("Show outline", "toc") { workspace.shell.inspectorOpen = true; workspace.shell.inspectorTab = .outline }
            sep()
            add("Add to revision", "timer") { workspace.addCurrentNoteToRevision() }

        case .tag(let tag):
            // 1m
            add("Notes with \(tag)", "sell") { workspace.open(.search(tag)) }
            add("Rename everywhere…", "edit") { workspace.dialog = .renameTag(tag) }
            sep()
            add("Remove from this note", "close", enabled: editable) { removeTag(tag, at: ctx.location, handle: handle) }
            add("Delete tag…", "delete") { workspace.dialog = .deleteTag(tag) }

        case .image:
            // 1h
            add("Copy", "content_copy", key: "c") { tv?.copy(nil) }
            sep()
            add("Delete image", "delete", enabled: editable) { deleteLine(lineIndex(of: ctx.location, handle: handle), handle: handle) }

        case .table:
            // 1i
            add("Insert row above", "vertical_align_top", enabled: editable) { TableEditing.apply(.insertRow(above: true), at: ctx.location, handle: handle) }
            add("Insert row below", "vertical_align_bottom", enabled: editable) { TableEditing.apply(.insertRow(above: false), at: ctx.location, handle: handle) }
            add("Insert column left", "keyboard_tab_rtl", enabled: editable) { TableEditing.apply(.insertColumn(left: true), at: ctx.location, handle: handle) }
            add("Insert column right", "keyboard_tab", enabled: editable) { TableEditing.apply(.insertColumn(left: false), at: ctx.location, handle: handle) }
            sep()
            submenu("Sort column", "sort") { sub in
                add("A → Z", enabled: editable, to: sub) { TableEditing.apply(.sort(ascending: true), at: ctx.location, handle: handle) }
                add("Z → A", enabled: editable, to: sub) { TableEditing.apply(.sort(ascending: false), at: ctx.location, handle: handle) }
            }
            submenu("Align column", "format_align_left") { sub in
                add("Left", enabled: editable, to: sub) { TableEditing.apply(.align(.left), at: ctx.location, handle: handle) }
                add("Center", enabled: editable, to: sub) { TableEditing.apply(.align(.center), at: ctx.location, handle: handle) }
                add("Right", enabled: editable, to: sub) { TableEditing.apply(.align(.right), at: ctx.location, handle: handle) }
            }
            sep()
            add("Delete row", "delete", enabled: editable) { TableEditing.apply(.deleteRow, at: ctx.location, handle: handle) }
            add("Delete column", "delete", enabled: editable) { TableEditing.apply(.deleteColumn, at: ctx.location, handle: handle) }

        case .plain:
            // 1c
            add("Cut", "content_cut", key: "x", enabled: false)
            add("Copy", "content_copy", key: "c", enabled: false)
            add("Paste", "content_paste", key: "v", enabled: editable) { tv?.paste(nil) }
            add("Paste as plain text", "content_paste_go", key: "v", mods: [.command, .shift], enabled: editable) { handle.pasteAsPlainText() }
            sep()
            submenu("Insert", "add_box") { sub in
                for (what, title, icon) in [(EditorInsertion.task, "Task", "check_box"), (.link, "Link to note", "add_link"),
                                            (.table, "Table", "table"), (.formula, "Formula", "functions"), (.date, "Date and time", "event"),
                                            (.callout, "Callout", "lightbulb"), (.code, "Code block", "code"), (.footnote, "Footnote", "notes"),
                                            (.divider, "Divider", "remove")] {
                    add(title, icon, enabled: editable, to: sub) { handle.insert(what, clock: workspace.env.clock) }
                }
            }
            add("Link to note…", "add_link", enabled: editable) { handle.insert(.link, clock: workspace.env.clock) }
            sep()
            add("Ask agent…", "auto_awesome", key: "j", enabled: false)
            sep()
            add("Select all", "select_all", key: "a") { tv?.selectAll(nil) }
            add(model.mode == .source ? "Live preview" : "Source mode", "code", key: "e", mods: [.command, .shift]) {
                model.setMode(model.mode == .source ? .live : .source)
            }
        }
        return menu
    }

    // MARK: Text actions behind the menus

    static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: "#-*> []").union(.whitespaces))
        return String(clean.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    static func lineIndex(of location: Int, handle: EditorHandle) -> Int {
        guard let tv = handle.textView else { return 0 }
        let text = tv.string as NSString
        return text.substring(to: min(location, text.length)).components(separatedBy: "\n").count - 1
    }

    static func deleteLine(_ line: Int, handle: EditorHandle) {
        guard let tv = handle.textView, let range = lineRange(line, in: tv.string as NSString) else { return }
        tv.replace(range, with: "")
    }

    /// Selection → a new note of the course; the selection becomes `[[Title]]`.
    static func extract(_ text: String, title: String, handle: EditorHandle, model: NoteEditorModel, workspace: Workspace) {
        guard let course = model.courseID, let tv = handle.textView else { return }
        let range = tv.selectedRange()
        let name = title.isEmpty ? "Extracted note" : title
        workspace.perform("Extract to new note") {
            _ = try await workspace.env.notes.create(course: course, title: name, kind: .note, text: text + "\n", actor: .user,
                                                     baseVersion: nil, dryRun: false, idempotencyKey: nil)
            tv.replace(range, with: "[[\(name)]]")
            await workspace.refreshAfterWrite()
            workspace.show("Moved to “\(name)”", icon: "call_split")
        }
    }

    /// The section under a heading (to the next heading of the same or a higher level).
    static func sectionRange(at location: Int, in text: NSString) -> (range: NSRange, level: Int)? {
        let start = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        let head = text.substring(with: start)
        let level = head.prefix { $0 == "#" }.count
        guard level > 0 else { return nil }
        var end = NSMaxRange(start)
        while end < text.length {
            let line = text.lineRange(for: NSRange(location: end, length: 0))
            let l = text.substring(with: line).prefix { $0 == "#" }.count
            if l > 0, l <= level, text.substring(with: line).dropFirst(l).hasPrefix(" ") { break }
            end = NSMaxRange(line)
        }
        return (NSRange(location: start.location, length: end - start.location), level)
    }

    static func extractSection(at location: Int, title: String, handle: EditorHandle, model: NoteEditorModel, workspace: Workspace) {
        guard let course = model.courseID, let tv = handle.textView else { return }
        let text = tv.string as NSString
        guard let (range, _) = sectionRange(at: location, in: text) else { return }
        let headLine = text.lineRange(for: NSRange(location: range.location, length: 0))
        let body = text.substring(with: NSRange(location: NSMaxRange(headLine), length: NSMaxRange(range) - NSMaxRange(headLine)))
        workspace.perform("Extract to new note") {
            _ = try await workspace.env.notes.create(course: course, title: title, kind: .note, text: "# \(title)\n\n" + body,
                                                     actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            tv.replace(range, with: "![[\(title)]]\n")
            await workspace.refreshAfterWrite()
            workspace.show("Section moved to “\(title)”", icon: "call_split")
        }
    }

    /// Swaps the section with the previous / next one of the same level.
    static func moveSection(at location: Int, up: Bool, handle: EditorHandle) {
        guard let tv = handle.textView else { return }
        let text = tv.string as NSString
        guard let (me, level) = sectionRange(at: location, in: text) else { return }
        if up {
            // The section before: the nearest heading of the same level above.
            var probe = me.location
            while probe > 0 {
                let line = text.lineRange(for: NSRange(location: probe - 1, length: 0))
                let l = text.substring(with: line).prefix { $0 == "#" }.count
                if l > 0, l <= level { break }
                probe = line.location
            }
            guard probe > 0 || text.substring(with: text.lineRange(for: NSRange(location: 0, length: 0))).hasPrefix("#") else { return }
            let prevStart = text.lineRange(for: NSRange(location: max(0, probe - 1), length: 0)).location
            guard let (prev, prevLevel) = sectionRange(at: prevStart, in: text), prevLevel == level, NSMaxRange(prev) == me.location else { return }
            let joined = withNewline(text.substring(with: me)) + text.substring(with: prev)
            tv.replace(NSRange(location: prev.location, length: NSMaxRange(me) - prev.location), with: joined)
        } else {
            guard NSMaxRange(me) < text.length, let (next, nextLevel) = sectionRange(at: NSMaxRange(me), in: text), nextLevel == level else { return }
            let joined = withNewline(text.substring(with: next)) + text.substring(with: me)
            tv.replace(NSRange(location: me.location, length: NSMaxRange(next) - me.location), with: joined)
        }
    }

    private static func withNewline(_ s: String) -> String { s.hasSuffix("\n") ? s : s + "\n" }

    /// A task becomes a note of the course; the line keeps the checkbox with a link to it.
    static func convertTask(line: Int, handle: EditorHandle, model: NoteEditorModel, workspace: Workspace) {
        guard let course = model.courseID, let tv = handle.textView,
              let range = lineRange(line, in: tv.string as NSString) else { return }
        let content = (tv.string as NSString).substring(with: range)
        let prefix = content.prefix { $0 == " " || $0 == "\t" } + "- [ ] "
        var words = content.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(6).split(separator: " ").map(String.init)
        words.removeAll { $0.hasPrefix("^") || $0.hasPrefix("@") }
        let title = String(words.joined(separator: " ").prefix(60))
        guard !title.isEmpty else { return }
        workspace.perform("Convert to note") {
            _ = try await workspace.env.notes.create(course: course, title: title, kind: .note, text: "# \(title)\n\n", actor: .user,
                                                     baseVersion: nil, dryRun: false, idempotencyKey: nil)
            tv.replace(range, with: prefix + "[[\(title)]]" + (content.hasSuffix("\n") ? "\n" : ""))
            await workspace.refreshAfterWrite()
        }
    }

    enum LinkPart { case alias, target }

    /// The `[[…]]` around `location`, as (range, target, alias).
    static func wikilink(at location: Int, in text: NSString) -> (range: NSRange, target: String, alias: String?)? {
        let line = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        let s = text.substring(with: line) as NSString
        guard let regex = try? NSRegularExpression(pattern: #"!?\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#) else { return nil }
        for m in regex.matches(in: s as String, range: NSRange(location: 0, length: s.length)) {
            let r = NSRange(location: line.location + m.range.location, length: m.range.length)
            guard NSLocationInRange(location, r) || location == NSMaxRange(r) else { continue }
            let target = s.substring(with: m.range(at: 1))
            let alias = m.range(at: 2).location != NSNotFound ? s.substring(with: m.range(at: 2)) : nil
            return (r, target, alias)
        }
        return nil
    }

    /// Selects the display text (adds `|Target` first when there is none) or the target.
    static func editLink(at location: Int, handle: EditorHandle, part: LinkPart) {
        guard let tv = handle.textView, let link = wikilink(at: location, in: tv.string as NSString) else { return }
        let open = (tv.string as NSString).substring(with: NSRange(location: link.range.location, length: 1)) == "!" ? 3 : 2
        switch part {
        case .target:
            tv.setSelectedRange(NSRange(location: link.range.location + open, length: (link.target as NSString).length))
        case .alias:
            if let alias = link.alias {
                let at = link.range.location + open + (link.target as NSString).length + 1
                tv.setSelectedRange(NSRange(location: at, length: (alias as NSString).length))
            } else {
                let at = NSMaxRange(link.range) - 2
                tv.replace(NSRange(location: at, length: 0), with: "|" + link.target)
                tv.setSelectedRange(NSRange(location: at + 1, length: (link.target as NSString).length))
            }
        }
        tv.window?.makeFirstResponder(tv)
    }

    /// `[[Target|Alias]]` → `Alias` (or `Target`).
    static func unlink(at location: Int, handle: EditorHandle) {
        guard let tv = handle.textView, let link = wikilink(at: location, in: tv.string as NSString) else { return }
        tv.replace(link.range, with: link.alias ?? link.target)
    }

    /// Removes one `#tag` (and the space before it) at `location`.
    static func removeTag(_ tag: String, at location: Int, handle: EditorHandle) {
        guard let tv = handle.textView else { return }
        let text = tv.string as NSString
        let line = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        let s = text.substring(with: line) as NSString
        var search = NSRange(location: 0, length: s.length)
        while true {
            let r = s.range(of: tag, options: [], range: search)
            guard r.location != NSNotFound else { return }
            let abs = NSRange(location: line.location + r.location, length: r.length)
            if NSLocationInRange(location, abs) || location == NSMaxRange(abs) {
                let before = r.location > 0 && s.character(at: r.location - 1) == 0x20
                tv.replace(before ? NSRange(location: abs.location - 1, length: abs.length + 1) : abs, with: "")
                return
            }
            search = NSRange(location: NSMaxRange(r), length: s.length - NSMaxRange(r))
        }
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
