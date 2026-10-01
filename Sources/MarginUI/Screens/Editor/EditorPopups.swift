import AppKit
import MarginCore
import SwiftUI

/// Shared popup surface (M10-00): white, 1 px `#E4E5E9`, radius 10, shadow `0 12 32 .16`, padding 5.
struct PopupSurface<Content: View>: View {
    var width: CGFloat
    var padding: CGFloat = 5
    var radius: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 1) { content }
            .padding(padding)
            .frame(width: width, alignment: .leading)
            .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(MarginColor.borderCard) }
            .marginShadow(.popover)
    }
}

/// Section label inside a popup („Blocks“, „Fall 2026“).
struct PopupSection: View {
    let title: String
    var body: some View {
        Text(title).marginFont(MarginTextSize.xs, .semibold).foregroundStyle(MarginColor.textTertiary)
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 4, trailing: 8))
    }
}

/// Editor popups: `[[` autocomplete (1c), slash commands (2a), link preview on hover (2b).
@MainActor @Observable
final class EditorPopupState {
    enum Kind { case none, link, slash }
    var kind: Kind = .none
    var query = ""
    /// Caret rect in window coordinates (AppKit, origin bottom left).
    var anchor: NSRect = .zero
    var selection = 0
    var links: [LinkSuggestion] = []
    var commands: [SlashCommand] = []
    var registry: SlashCommandRegistry?
    var preview: (title: String, course: Course?, excerpt: NoteExcerpt, noteID: NoteID)?
    var previewAnchor: NSRect = .zero
    var showStyleMenu = false
    /// 1d: selection rect (window coordinates) while text is selected.
    var selectionRect: NSRect?
    private var previewTask: Task<Void, Never>?
    private var linkTask: Task<Void, Never>?

    func link(_ q: String?, at rect: NSRect, workspace: Workspace, course: CourseID?, note: NoteID?) {
        guard let q else { if kind == .link { kind = .none }; return }
        kind = .link
        query = q
        anchor = rect
        linkTask?.cancel()
        linkTask = Task { @MainActor [weak self] in
            let found = (try? await workspace.env.search.suggestLinks(prefix: q, course: course, note: note, limit: 8)) ?? []
            guard !Task.isCancelled, let self, self.kind == .link, self.query == q else { return }
            self.links = found
            self.selection = min(self.selection, max(0, found.count - 1))
        }
    }

    func slash(_ q: String?, at rect: NSRect, clock: any Clock) {
        guard let q else { if kind == .slash { kind = .none }; return }
        if registry == nil { registry = SlashCommandRegistry(clock: clock) }
        kind = .slash
        query = q
        anchor = rect
        commands = registry?.matching(q) ?? []
        selection = min(selection, max(0, commands.count - 1))
    }

    func hover(_ target: String?, at rect: NSRect, workspace: Workspace) {
        previewTask?.cancel()
        guard let target else {
            previewTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { self?.preview = nil }
            }
            return
        }
        previewAnchor = rect
        // Shows within 150 ms of resting on the link (M10-05).
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            guard let id = await workspace.resolve(link: target) else { return }
            let excerpt = (try? await workspace.env.search.excerpt(note: id, heading: nil)) ?? NoteExcerpt(text: "")
            let course = workspace.courses.courseID(ofNote: id).flatMap { workspace.courses.course(id: $0) }
            guard !Task.isCancelled else { return }
            self.preview = (target, course, excerpt, id)
        }
    }

    /// Keys while a popup is open; returns true when handled.
    func key(_ key: EditorKey, handle: EditorHandle, workspace: Workspace) -> Bool {
        let count = kind == .link ? links.count : commands.count
        switch key {
        case .up: selection = (selection - 1 + max(count, 1)) % max(count, 1); return true
        case .down: selection = (selection + 1) % max(count, 1); return true
        case .enter, .tab: return choose(selection, handle: handle)
        case .escape: kind = .none; return true
        }
    }

    @discardableResult
    func choose(_ index: Int, handle: EditorHandle) -> Bool {
        guard let coordinator = handle.textView?.coordinator else { return false }
        switch kind {
        case .link:
            guard let start = coordinator.linkQueryStart else { return false }
            let text: String
            if links.indices.contains(index) { text = "[[\(links[index].insertText)]]" }
            else if !query.isEmpty { text = "[[\(query)]]" }
            else { return false }
            kind = .none
            handle.replaceQuery(from: start, with: text)
            return true
        case .slash:
            guard let start = coordinator.slashStart, commands.indices.contains(index),
                  let insertion = registry?.insertion(for: commands[index].kind) else { return false }
            kind = .none
            handle.replaceQuery(from: start, with: insertion.text, caretOffset: insertion.cursorOffset)
            return true
        case .none:
            return false
        }
    }
}

struct EditorPopups: View {
    let state: EditorPopupState
    let model: NoteEditorModel
    let handle: EditorHandle
    @Environment(Workspace.self) private var workspace

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let windowHeight = handle.textView?.window?.contentView?.frame.height ?? geo.size.height
            let caret = CGPoint(x: state.anchor.minX - origin.x, y: windowHeight - state.anchor.minY - origin.y)
            ZStack(alignment: .topLeading) {
                Color.clear
                switch state.kind {
                case .link:
                    LinkAutocomplete(state: state, courseName: model.courseID.flatMap { workspace.courses.course(id: $0)?.name }) {
                        state.choose($0, handle: handle)
                    }
                    .offset(x: max(8, min(caret.x - 20, geo.size.width - 350)), y: caret.y + 6)
                case .slash:
                    SlashMenu(state: state) { state.choose($0, handle: handle) }
                        .offset(x: max(8, min(caret.x - 12, geo.size.width - 310)), y: caret.y + 6)
                case .none:
                    EmptyView()
                }
                if let sel = state.selectionRect, state.kind == .none {
                    let top = windowHeight - sel.maxY - origin.y
                    SelectionToolbar(handle: handle) { state.selectionRect = nil }
                        .offset(x: max(8, min(sel.minX - origin.x, geo.size.width - 380)), y: max(4, top - 48))
                }
                if let preview = state.preview {
                    let p = CGPoint(x: state.previewAnchor.minX - origin.x, y: windowHeight - state.previewAnchor.minY - origin.y)
                    LinkPreviewCard(title: preview.title, course: preview.course, excerpt: preview.excerpt) {
                        workspace.open(.note(preview.noteID), title: preview.title)
                        state.preview = nil
                    }
                    .offset(x: max(8, min(p.x - 60, geo.size.width - 390)), y: p.y + 14)
                    .onHover { inside in if !inside { state.preview = nil } }
                }
            }
        }
        .allowsHitTesting(state.kind != .none || state.preview != nil || state.selectionRect != nil)
    }
}

/// 1c: suggestions after `[[`, create option, key hints.
private struct LinkAutocomplete: View {
    let state: EditorPopupState
    let courseName: String?
    let choose: (Int) -> Void

    var body: some View {
        PopupSurface(width: 340) {
            ForEach(Array(state.links.enumerated()), id: \.element.id) { index, s in
                if s.kind != .create {
                    Button { choose(index) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            highlighted(s.title)
                                .marginFont(MarginTextSize.base)
                                .foregroundStyle(index == state.selection ? MarginColor.accentText : MarginColor.ink)
                            if let detail = s.detail {
                                Text(detail).marginFont(MarginTextSize.xs)
                                    .foregroundStyle(index == state.selection ? MarginColor.textSecondary : MarginColor.textTertiary)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == state.selection ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !state.query.isEmpty {
                MarginDivider(color: Color(hex: 0xEDEEF1)).padding(.horizontal, 8).padding(.vertical, 4)
                let createIndex = state.links.firstIndex { $0.kind == .create } ?? state.links.count
                Button { choose(createIndex) } label: {
                    HStack(spacing: 8) {
                        Icon("add", size: 16, color: MarginColor.textSecondary)
                        Text("Create “\(state.query)”\(courseName.map { " in \($0)" } ?? "")")
                    }
                    .marginFont(14).foregroundStyle(MarginColor.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(createIndex == state.selection ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Text("↑↓ navigate"); Text("↵ link"); Text("# heading"); Text("| alias")
            }
            .marginFont(11).foregroundStyle(MarginColor.textTertiary)
            .padding(EdgeInsets(top: 6, leading: 10, bottom: 4, trailing: 10))
        }
    }

    private func highlighted(_ title: String) -> Text {
        guard !state.query.isEmpty, let r = title.range(of: state.query, options: .caseInsensitive) else { return Text(title) }
        return Text(title[..<r.lowerBound]) + Text(title[r]).bold() + Text(title[r.upperBound...])
    }
}

/// 2a: slash commands grouped (Blocks, Inline) with their Markdown hint.
private struct SlashMenu: View {
    let state: EditorPopupState
    let choose: (Int) -> Void

    var body: some View {
        PopupSurface(width: 300) {
            let groups = Dictionary(grouping: Array(state.commands.enumerated()), by: { $0.element.group })
            ForEach(["Blocks", "Inline", "School"].filter { groups[$0] != nil } + groups.keys.filter { !["Blocks", "Inline", "School"].contains($0) }.sorted(), id: \.self) { group in
                PopupSection(title: group)
                ForEach(groups[group] ?? [], id: \.element.id) { index, command in
                    let on = index == state.selection
                    Button { choose(index) } label: {
                        HStack(spacing: 10) {
                            Icon(Self.icon(command.kind), size: 18, color: on ? MarginColor.accentText : MarginColor.textSecondary)
                            Text(command.title).frame(maxWidth: .infinity, alignment: .leading)
                            Text(Self.hint(command.kind)).marginFont(MarginTextSize.xs)
                                .foregroundStyle(on ? MarginColor.accentText : MarginColor.textTertiary)
                        }
                        .marginFont(14)
                        .foregroundStyle(on ? MarginColor.accentText : MarginColor.ink)
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .background(on ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if state.commands.isEmpty {
                Text("No command “\(state.query)”").marginFont(14).foregroundStyle(MarginColor.textTertiary).padding(8)
            }
        }
    }

    static func icon(_ k: SlashCommand.Kind) -> String {
        switch k {
        case .heading1, .heading2, .heading3: "title"
        case .task: "check_box"
        case .bullet: "format_list_bulleted"
        case .numbered: "format_list_numbered"
        case .quote: "format_quote"
        case .callout: "info"
        case .code: "code"
        case .table: "table"
        case .divider: "horizontal_rule"
        case .dateToday: "calendar_today"
        case .link: "link"
        case .embed: "image"
        }
    }

    static func hint(_ k: SlashCommand.Kind) -> String {
        switch k {
        case .heading1: "#"
        case .heading2: "##"
        case .heading3: "###"
        case .task: "- [ ]"
        case .bullet: "-"
        case .numbered: "1."
        case .quote: ">"
        case .callout: "> [!]"
        case .code: "```"
        case .table: "|"
        case .divider: "---"
        case .dateToday: "@"
        case .link: "[[ ]]"
        case .embed: "![[ ]]"
        }
    }
}

/// 2b: preview card of a linked note.
struct LinkPreviewCard: View {
    let title: String
    let course: Course?
    let excerpt: NoteExcerpt
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let course { Circle().fill(Color(hexString: course.style.dot)).frame(width: 7, height: 7) }
                Text(course?.name ?? "Note").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textSecondary)
                Spacer()
                Button(action: onOpen) { Icon("open_in_new", size: 16, color: MarginColor.textSecondary) }
                    .buttonStyle(.plain).help("Open")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            MarginDivider(color: Color(hex: 0xEDEEF1))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).marginFont(18, .bold).tracking(-0.3)
                Text(excerpt.isEmpty ? "Empty note" : excerpt.text)
                    .marginFont(14).lineSpacing(3)
                    .foregroundStyle(excerpt.isEmpty ? MarginColor.textTertiary : MarginColor.ink)
                    .lineLimit(8)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .frame(width: 380, alignment: .leading)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MarginColor.borderCard) }
        .shadow(color: MarginColor.ink.opacity(0.18), radius: 20, y: 16)
        .onTapGesture(perform: onOpen)
    }
}

/// 2i Text style: the block type of the caret's line, checked, and what it can turn into.
struct TextStyleMenu: View {
    let handle: EditorHandle
    let close: () -> Void

    var body: some View {
        let current = handle.currentBlock
        let editable = handle.isAvailable
        VStack(alignment: .leading, spacing: 1) {
            row("Heading 1", "format_h1", "⌘⌥1", .heading1, current, editable)
            row("Heading 2", "format_h2", "⌘⌥2", .heading2, current, editable)
            row("Heading 3", "format_h3", "⌘⌥3", .heading3, current, editable)
            row("Paragraph", "notes", "⌘⌥0", .paragraph, current, editable)
            MarginDivider(color: Color(hex: 0xEDEEF1)).padding(.vertical, 4)
            row("Quote", "format_quote", "", .quote, current, editable)
            row("Callout", "lightbulb", "", .callout, current, editable)
            row("Code block", "code", "", .codeBlock, current, editable)
        }
        .padding(5)
        .frame(width: 230)
    }

    private func row(_ title: String, _ icon: String, _ key: String, _ block: EditorBlock, _ current: EditorBlock?,
                     _ editable: Bool) -> some View {
        MenuRow(title: title, icon: icon, shortcut: key, checked: current == block, disabled: !editable || current == block) {
            handle.setBlock(block); close()
        }
    }
}

/// Tooltip only when there is something to say (3d: why an item is disabled).
struct OptionalTooltip: ViewModifier {
    let text: String?
    var placement: TooltipPlacement = .bottom

    func body(content: Content) -> some View {
        if let text, !text.isEmpty { content.marginTooltip(text, shortcut: nil, placement: placement) } else { content }
    }
}

/// A row of every Margin menu (Margin Menus 4a): icon, label, shortcut; hover `#F0F1F4`, 30 px.
struct MenuRow: View {
    let title: String
    var icon: String?
    var shortcut: String = ""
    var checked = false
    var destructive = false
    var disabled = false
    var help: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if checked { Icon("check", size: 14, color: MarginColor.ink).frame(width: 16) }
                else if let icon { Icon(icon, size: 16, color: destructive ? MarginColor.due : MarginColor.textSecondary).frame(width: 16) }
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                if !shortcut.isEmpty { Text(shortcut).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary) }
            }
            .marginFont(14)
            .foregroundStyle(disabled ? MarginColor.textDisabled : destructive ? MarginColor.due : MarginColor.ink)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(hovered && !disabled ? MarginColor.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered = $0 }
        .modifier(OptionalTooltip(text: help, placement: .trailing))
    }
}

/// 1d Selection toolbar: dark, over the selection. Formatting works now; Explain and Flashcard
/// belong to the in-app agent (MA3) and stay disabled.
struct SelectionToolbar: View {
    let handle: EditorHandle
    let done: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            item("Explain", "auto_awesome", enabled: false) {}
            item("Flashcard", "style", enabled: false) {}
            item("Link", "add_link") { handle.wrapSelection("[[", "]]") }
            Rectangle().fill(Color(hex: 0x4A4D57)).frame(width: 1, height: 18).padding(.horizontal, 4)
            icon("format_bold", "Bold") { handle.wrapSelection("**", "**") }
            icon("format_italic", "Italic") { handle.wrapSelection("*", "*") }
            icon("check_box", "Make task") { handle.wrapSelection("- [ ] ", "") }
        }
        .padding(4)
        .background(MarginColor.ink, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: MarginColor.ink.opacity(0.25), radius: 14, y: 10)
    }

    private func item(_ title: String, _ icon: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button { action(); done() } label: {
            HStack(spacing: 6) { Icon(icon, size: 15, color: .white); Text(title).marginFont(MarginTextSize.sm).foregroundStyle(.white) }
                .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .marginTooltip(enabled ? title : "\(title) comes with the in-app agent", shortcut: nil, placement: .top)
    }

    private func icon(_ name: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button { action(); done() } label: {
            Icon(name, size: 16, color: .white).frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marginTooltip(help, shortcut: nil, placement: .top)
    }
}
