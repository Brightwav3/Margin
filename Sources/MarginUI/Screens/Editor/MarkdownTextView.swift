import AppKit
import MarginCore
import SwiftUI

/// Typing behaviour from Settings › Editor (applied app-wide by `Workspace.applySettings`).
@MainActor enum EditorTyping {
    /// Return continues a list or task, an empty item ends it.
    static var smartLists = true
    /// Typing an opener adds its closer: `(` `[` `{` `"` `` ` `` and `**`, `==` around a selection.
    static var autoPair = true

    static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`"]

    /// The text to insert for `typed` at `selection`, and where the caret goes (relative to the
    /// start of the replaced range); nil when auto-pairing does not apply.
    static func pair(typed: String, selected: String, next: Character?) -> (text: String, caret: Int, length: Int)? {
        guard autoPair, let close = pairs[typed] else { return nil }
        if !selected.isEmpty { return (typed + selected + close, (typed + selected + close).utf16.count, 0) }
        // Before a letter or digit the pair would be in the way: type the opener alone.
        if let next, next.isLetter || next.isNumber { return nil }
        return (typed + close, typed.utf16.count, 0)
    }
}

/// Events the editor reports to its host (popups, navigation).
@MainActor
struct EditorEvents {
    var onOpenLink: (String) -> Void = { _ in }
    /// Typing after `[[` (M10-03): the query and the caret rect in window coordinates; nil closes.
    var onLinkQuery: (String?, NSRect) -> Void = { _, _ in }
    /// Typing after `/` at the start of a line (M10-04); nil closes.
    var onSlashQuery: (String?, NSRect) -> Void = { _, _ in }
    /// Hover over a wikilink (M10-05); nil when the pointer leaves it.
    var onHoverLink: (String?, NSRect) -> Void = { _, _ in }
    /// Right click (M10-31): what is under the pointer.
    var onContextMenu: (EditorContext) -> NSMenu? = { _ in nil }
    /// Selection changed (1d toolbar): the selection rect in window coordinates, nil when empty.
    var onSelection: (NSRect?) -> Void = { _ in }
    /// Keys the popup handles while open (↑ ↓ ⏎ ⎋ ⇥); returns true when consumed.
    var onPopupKey: (EditorKey) -> Bool = { _ in false }
}

enum EditorKey { case up, down, enter, escape, tab }

/// What a right click hit (Margin Menus 1c–1i).
struct EditorContext {
    enum Kind { case plain, selection(String), link(String), task(line: Int), heading(String), tag(String), image, table }
    var kind: Kind
    var location: Int
}

/// Handle the SwiftUI editor view keeps to act on the text view (insert, reveal, focus).
@MainActor
final class EditorHandle {
    weak var textView: MarginTextView?

    /// Replaces the characters between `from` and the caret with `text` (undoable) — completes `[[q` or `/q`.
    func replaceQuery(from: Int, with text: String, caretOffset: Int? = nil) {
        guard let tv = textView else { return }
        let caret = tv.selectedRange().location
        let range = NSRange(location: from, length: max(0, caret - from))
        tv.replace(range, with: text)
        let at = from + (caretOffset ?? (text as NSString).length)
        tv.setSelectedRange(NSRange(location: at, length: 0))
    }

    func insert(_ text: String) {
        guard let tv = textView else { return }
        tv.replace(tv.selectedRange(), with: text)
    }

    /// Scrolls to a 0-based line and marks it (task source, outline heading).
    func reveal(line: Int) {
        guard let tv = textView else { return }
        let text = tv.string as NSString
        var location = 0
        for _ in 0..<line where location < text.length {
            location = NSMaxRange(text.lineRange(for: NSRange(location: location, length: 0)))
        }
        let range = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        tv.setSelectedRange(NSRange(location: range.location, length: 0))
        tv.scrollRangeToVisible(range)
        tv.showFindIndicator(for: NSRange(location: range.location, length: max(0, range.length - 1)))
    }

    func focus() { textView?.window?.makeFirstResponder(textView) }

    var selectedText: String {
        guard let tv = textView else { return "" }
        return (tv.string as NSString).substring(with: tv.selectedRange())
    }

    func wrapSelection(_ prefix: String, _ suffix: String) {
        guard let tv = textView else { return }
        let r = tv.selectedRange()
        let s = (tv.string as NSString).substring(with: r)
        tv.replace(r, with: prefix + s + suffix)
        tv.setSelectedRange(NSRange(location: r.location + (prefix as NSString).length, length: r.length))
    }

    /// Caret rect in window coordinates.
    var caretRect: NSRect { textView?.caretRectInWindow ?? .zero }
}

/// The Markdown editor (M6): an `NSTextView` on TextKit 1 inside a SwiftUI scroll view. It
/// does not scroll itself; its height follows the text so the title and properties scroll with it.
struct MarkdownTextView: NSViewRepresentable {
    let text: String
    let revision: Int
    let mode: EditorMode
    let onEdit: (String) -> Void
    let events: EditorEvents
    let handle: EditorHandle

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MarginTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = false
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let tv = MarginTextView(frame: .zero, textContainer: container)
        tv.coordinator = context.coordinator
        layout.delegate = context.coordinator
        storage.delegate = context.coordinator
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.insertionPointColor = NSColor(MarginColor.accent)
        tv.selectedTextAttributes = [.backgroundColor: NSColor(MarginColor.accentRing)]
        tv.linkTextAttributes = [:]
        tv.setAccessibilityIdentifier("note-editor")
        tv.setAccessibilityLabel("Note text")
        handle.textView = tv
        context.coordinator.load(text, mode: mode, into: tv)
        return tv
    }

    func updateNSView(_ tv: MarginTextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        handle.textView = tv
        if c.revision != revision || c.mode != mode {
            let caret = tv.selectedRange()
            c.load(text, mode: mode, into: tv)
            tv.setSelectedRange(NSRange(location: min(caret.location, (tv.string as NSString).length), length: 0))
        }
        tv.isEditable = mode != .reading
        tv.isSelectable = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: MarginTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 700
        guard let container = tv.textContainer, let layout = tv.layoutManager else { return nil }
        if abs(container.size.width - width) > 0.5 {
            container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: width, height: ceil(used.height + tv.textContainerInset.height * 2 + 24))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate,
        @preconcurrency NSLayoutManagerDelegate {
        var parent: MarkdownTextView
        var tokenizer = MarkdownTokenizer()
        var blocks = BlockModel(text: "")
        var revision = -1
        var mode: EditorMode = .live
        /// Block under the caret (live mode shows its syntax).
        var active: MarkdownRange?
        private var loading = false
        private var pendingRestyle: NSRange?

        init(_ parent: MarkdownTextView) { self.parent = parent }

        func load(_ text: String, mode: EditorMode, into tv: MarginTextView) {
            loading = true
            defer { loading = false }
            revision = parent.revision
            self.mode = mode
            tokenizer = MarkdownTokenizer(text: text)
            blocks = tokenizer.blockModel()
            guard let storage = tv.textStorage else { return }
            if storage.string != text {
                tv.undoManager?.removeAllActions()
                storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            }
            active = mode == .live ? blocks.activeBlock(at: min(tv.selectedRange().location, storage.length)).range : nil
            restyle(NSRange(location: 0, length: storage.length), storage)
            tv.typingAttributes = MarkdownStyler.baseAttributes(mode)
            tv.needsDisplay = true
        }

        func restyle(_ range: NSRange, _ storage: NSTextStorage) {
            let tokens = tokenizer.tokens(in: MarkdownRange(location: range.location, length: range.length))
            MarkdownStyler.apply(to: storage, range: range, tokens: tokens, mode: mode, active: active)
        }

        // MARK: Text storage → tokenizer (incremental)

        func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !loading else { return }
            let replaced = MarkdownRange(location: editedRange.location, length: max(0, editedRange.length - delta))
            let replacement = (storage.string as NSString).substring(with: editedRange)
            let update = tokenizer.update(edit: replaced, replacement: replacement)
            blocks = tokenizer.blockModel()
            // Restyle after the edit is processed (attributes only), covering the retokenized lines.
            let changed = NSRange(location: update.changedRange.location, length: update.changedRange.length)
            pendingRestyle = pendingRestyle.map { NSUnionRange($0, changed) } ?? changed
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? MarginTextView, let storage = tv.textStorage else { return }
            if var r = pendingRestyle {
                pendingRestyle = nil
                let text = storage.string as NSString
                r = text.lineRange(for: NSIntersectionRange(r, NSRange(location: 0, length: text.length)))
                updateActive(tv, force: true, extra: r)
            }
            parent.onEdit(storage.string)
            detectQueries(tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? MarginTextView, !loading else { return }
            updateActive(tv, force: false, extra: nil)
            detectQueries(tv)
            parent.events.onSelection(tv.selectedRange().length > 0 ? tv.selectionRectInWindow : nil)
        }

        /// Live mode: when the caret enters another block, restyle the old and new one.
        private func updateActive(_ tv: MarginTextView, force: Bool, extra: NSRange?) {
            guard let storage = tv.textStorage else { return }
            let length = storage.length
            var dirty = extra
            if mode == .live {
                let caret = min(tv.selectedRange().location, length)
                let block = blocks.activeBlock(at: caret).range
                if block != active || force {
                    if let old = active { dirty = union(dirty, NSRange(location: old.location, length: old.length)) }
                    dirty = union(dirty, NSRange(location: block.location, length: block.length))
                    active = block
                }
            }
            guard var r = dirty else { return }
            r = NSIntersectionRange(r, NSRange(location: 0, length: length))
            let text = storage.string as NSString
            r = text.lineRange(for: r)
            restyle(r, storage)
            tv.needsDisplay = true
        }

        private func union(_ a: NSRange?, _ b: NSRange) -> NSRange { a.map { NSUnionRange($0, b) } ?? b }

        // MARK: Popups (`[[`, `/`)

        /// Start of the `[[` query / `/` command before the caret, for the host to replace.
        private(set) var linkQueryStart: Int?
        private(set) var slashStart: Int?

        private func detectQueries(_ tv: MarginTextView) {
            let sel = tv.selectedRange()
            let text = tv.string as NSString
            guard sel.length == 0, mode != .reading else { close(); return }
            let line = text.lineRange(for: NSRange(location: sel.location, length: 0))
            let before = text.substring(with: NSRange(location: line.location, length: sel.location - line.location))
            if let open = before.range(of: "[[", options: .backwards), !before[open.upperBound...].contains("]") {
                let query = String(before[open.upperBound...])
                linkQueryStart = line.location + (before.utf16.distance(from: before.utf16.startIndex,
                                                                           to: open.lowerBound.samePosition(in: before.utf16)!))
                slashStart = nil
                parent.events.onLinkQuery(query, tv.caretRectInWindow)
                return
            }
            let trimmed = before.drop { $0 == " " || $0 == "\t" }
            if trimmed.hasPrefix("/"), !trimmed.contains(" ") {
                slashStart = sel.location - (trimmed as Substring).utf16.count
                linkQueryStart = nil
                parent.events.onSlashQuery(String(trimmed.dropFirst()), tv.caretRectInWindow)
                return
            }
            close()
        }

        private func close() {
            if linkQueryStart != nil { parent.events.onLinkQuery(nil, .zero) }
            if slashStart != nil { parent.events.onSlashQuery(nil, .zero) }
            linkQueryStart = nil
            slashStart = nil
        }

        var popupOpen: Bool { linkQueryStart != nil || slashStart != nil }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard let text, text.utf16.count == 1, let tv = textView as? MarginTextView else { return true }
            let string = tv.string as NSString
            // Typing the closer that auto-pairing already put there steps over it.
            if EditorTyping.autoPair, range.length == 0, EditorTyping.pairs.values.contains(text),
               range.location < string.length, string.substring(with: NSRange(location: range.location, length: 1)) == text,
               range.location > 0, EditorTyping.pairs[string.substring(with: NSRange(location: range.location - 1, length: 1))] == text {
                tv.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                return false
            }
            let next: Character? = NSMaxRange(range) < string.length
                ? string.substring(with: NSRange(location: NSMaxRange(range), length: 1)).first : nil
            guard let pair = EditorTyping.pair(typed: text, selected: string.substring(with: range), next: next) else { return true }
            tv.replace(range, with: pair.text)
            tv.setSelectedRange(NSRange(location: range.location + pair.caret, length: pair.length))
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard popupOpen else {
                if selector == #selector(NSResponder.insertNewline(_:)), EditorTyping.smartLists { return continueList(textView) }
                return false
            }
            let key: EditorKey? = switch selector {
            case #selector(NSResponder.moveUp(_:)): .up
            case #selector(NSResponder.moveDown(_:)): .down
            case #selector(NSResponder.insertNewline(_:)): .enter
            case #selector(NSResponder.cancelOperation(_:)): .escape
            case #selector(NSResponder.insertTab(_:)): .tab
            default: nil
            }
            guard let key else { return false }
            if key == .escape { close(); return true }
            return parent.events.onPopupKey(key)
        }

        /// Return in a list or task continues it (`- `, `- [ ] `, `1. `); on an empty item it ends the list.
        private func continueList(_ tv: NSTextView) -> Bool {
            let text = tv.string as NSString
            let caret = tv.selectedRange().location
            let line = text.lineRange(for: NSRange(location: caret, length: 0))
            let content = text.substring(with: NSRange(location: line.location, length: caret - line.location))
            let indent = String(content.prefix { $0 == " " || $0 == "\t" })
            let rest = content.dropFirst(indent.count)
            var marker: String?
            for prefix in ["- [ ] ", "- [x] ", "* [ ] ", "- ", "* ", "+ "] where rest.hasPrefix(prefix) {
                marker = prefix.replacingOccurrences(of: "[x]", with: "[ ]"); break
            }
            if marker == nil, let dot = rest.firstIndex(of: "."), let n = Int(rest[..<dot]), rest[dot...].hasPrefix(". ") {
                marker = "\(n + 1). "
            }
            guard let marker else { return false }
            let body = rest.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            let markerLen = (indent + marker).utf16.count
            if body.isEmpty && caret - line.location <= markerLen + 1 {
                (tv as? MarginTextView)?.replace(NSRange(location: line.location, length: caret - line.location), with: "")
                return true
            }
            (tv as? MarginTextView)?.replace(tv.selectedRange(), with: "\n" + indent + marker)
            return true
        }

        // MARK: Hidden syntax

        func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                           properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                           characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
            guard let storage = layoutManager.textStorage else { return 0 }
            var hidden = false
            for i in 0..<range.length where characterIndexes[i] < storage.length {
                if storage.attribute(.marginHidden, at: characterIndexes[i], effectiveRange: nil) != nil { hidden = true; break }
            }
            guard hidden else { return 0 }
            let modified = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: range.length)
            defer { modified.deallocate() }
            for i in 0..<range.length {
                var p = props[i]
                let ci = characterIndexes[i]
                if ci < storage.length, storage.attribute(.marginHidden, at: ci, effectiveRange: nil) != nil {
                    p.insert(.null)
                }
                modified[i] = p
            }
            layoutManager.setGlyphs(glyphs, properties: modified, characterIndexes: characterIndexes, font: font,
                                    forGlyphRange: range)
            return range.length
        }

        /// Hidden newlines (frontmatter, fences) take no line.
        func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                           forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
            guard let storage = layoutManager.textStorage, charIndex < storage.length,
                  storage.attribute(.marginHidden, at: charIndex, effectiveRange: nil) != nil else { return action }
            return .zeroAdvancement
        }
    }
}

/// The text view: draws task checkboxes and handles clicks on them and on links.
final class MarginTextView: NSTextView {
    weak var coordinator: MarkdownTextView.Coordinator?
    private var hoverTracking: NSTrackingArea?
    private var hoveredLink: String?

    /// The container follows the width SwiftUI gives the view (text wraps at the column width).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let container = textContainer, abs(container.size.width - newSize.width) > 0.5 {
            container.size = NSSize(width: newSize.width, height: .greatestFiniteMagnitude)
        }
    }

    /// Replaces characters as a user edit (undoable, notifies the delegate).
    func replace(_ range: NSRange, with text: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
    }

    /// Bounding rect of the selection in window coordinates.
    var selectionRectInWindow: NSRect? {
        guard let layout = layoutManager, let container = textContainer, selectedRange().length > 0 else { return nil }
        let glyphs = layout.glyphRange(forCharacterRange: selectedRange(), actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return convert(rect, to: nil)
    }

    var caretRectInWindow: NSRect {
        guard let layout = layoutManager, let container = textContainer else { return .zero }
        let caret = min(selectedRange().location, (string as NSString).length)
        var rect: NSRect
        if (string as NSString).length == 0 {
            rect = NSRect(x: 0, y: 0, width: 1, height: 20)
        } else {
            let glyph = layout.glyphIndexForCharacter(at: max(0, caret == (string as NSString).length ? caret - 1 : caret))
            rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            if caret == (string as NSString).length { rect.origin.x = rect.maxX }
        }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return convert(rect, to: nil)
    }

    // MARK: Checkboxes

    private func checkboxes(in dirty: NSRect) -> [(rect: NSRect, checked: Bool, char: Int)] {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return [] }
        var result: [(NSRect, Bool, Int)] = []
        let glyphs = layout.glyphRange(forBoundingRect: dirty, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.marginCheckbox, in: chars) { value, range, _ in
            guard let checked = value as? Bool else { return }
            let g = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var r = layout.boundingRect(forGlyphRange: g, in: container)
            r.origin.x += textContainerOrigin.x
            r.origin.y += textContainerOrigin.y
            let side: CGFloat = 16
            let box = NSRect(x: r.minX + (r.width - side) / 2, y: r.midY - side / 2, width: side, height: side)
            result.append((box.integral, checked, range.location))
        }
        return result
    }

    /// Round bullets over the invisible `-` of list items.
    private func bullets(in dirty: NSRect) -> [NSRect] {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return [] }
        var result: [NSRect] = []
        let glyphs = layout.glyphRange(forBoundingRect: dirty, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.marginBullet, in: chars) { value, range, _ in
            guard value as? Bool == true else { return }
            for i in 0..<range.length {
                let g = layout.glyphRange(forCharacterRange: NSRange(location: range.location + i, length: 1), actualCharacterRange: nil)
                var r = layout.boundingRect(forGlyphRange: g, in: container)
                r.origin.x += textContainerOrigin.x
                r.origin.y += textContainerOrigin.y
                let side: CGFloat = 5.5 * MarkdownStyler.scale
                // On the x-height of the text, not the middle of the tall line box.
                let line = layout.lineFragmentRect(forGlyphAt: g.location, effectiveRange: nil)
                // `location(forGlyphAt:)` is the baseline within the line fragment (flipped view).
                let baseline = line.minY + layout.location(forGlyphAt: g.location).y + textContainerOrigin.y
                let y = baseline - MarkdownStyler.bodyFont().xHeight / 2 - side / 2
                result.append(NSRect(x: r.midX - side / 2, y: y, width: side, height: side))
            }
        }
        return result
    }

    /// Pictures of `![[…]]` embeds, in the lines the styler reserved.
    private func embeds(in dirty: NSRect) -> [(rect: NSRect, image: NSImage)] {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return [] }
        var result: [(NSRect, NSImage)] = []
        let glyphs = layout.glyphRange(forBoundingRect: dirty.insetBy(dx: 0, dy: -800), in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.marginEmbed, in: chars) { value, range, _ in
            guard let value = value as? String else { return }
            let parts = value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let image = EmbedImages.shared.image(parts[0]) else { return }
            let g = layout.glyphIndexForCharacter(at: range.location)
            let line = layout.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let maxWidth = min(MarkdownStyler.maxEmbedWidth, container.size.width - container.lineFragmentPadding * 2)
            let size = EmbedImages.displaySize(of: image, spec: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil, maxWidth: maxWidth)
            let x = textContainerOrigin.x + line.minX + container.lineFragmentPadding
            let rect = NSRect(x: x, y: textContainerOrigin.y + line.minY + 6, width: size.width, height: size.height)
            result.append((rect, image))
        }
        return result
    }

    /// Markdown tables drawn as grids (live and reading, outside the table being edited).
    private func drawTables(in dirty: NSRect) {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return }
        let glyphs = layout.glyphRange(forBoundingRect: dirty.insetBy(dx: 0, dy: -1200), in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.marginTable, in: chars) { value, range, _ in
            guard let source = value as? String else { return }
            let g = layout.glyphIndexForCharacter(at: range.location)
            let line = layout.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            var rows = source.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(TableEditing.cells)
            var aligns: [NSTextAlignment] = []
            if let d = rows.firstIndex(where: TableEditing.isDelimiter) {
                aligns = rows[d].map { c in c.hasPrefix(":") && c.hasSuffix(":") ? .center : c.hasSuffix(":") ? .right : .left }
                rows.remove(at: d)
            }
            guard !rows.isEmpty else { return }
            let columns = rows.map(\.count).max() ?? 1
            let font = MarkdownStyler.bodyFont(size: 15), bold = MarkdownStyler.bodyFont(.semibold, size: 15)
            func plain(_ s: String) -> String {
                s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "==", with: "")
                    .replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "\\|", with: "|")
                    .replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
            }
            var widths = Array(repeating: CGFloat(60), count: columns)
            for (r, row) in rows.enumerated() {
                for (c, cell) in row.enumerated() where c < columns {
                    let w = (plain(cell) as NSString).size(withAttributes: [.font: r == 0 ? bold : font]).width + 28
                    widths[c] = max(widths[c], w)
                }
            }
            let available = container.size.width - container.lineFragmentPadding * 2
            let total = widths.reduce(0, +)
            if total > available { widths = widths.map { $0 * available / total } }
            let rowH = MarkdownStyler.tableRowHeight
            let origin = NSPoint(x: textContainerOrigin.x + line.minX + container.lineFragmentPadding,
                                 y: textContainerOrigin.y + line.minY + 6)
            let frame = NSRect(x: origin.x, y: origin.y, width: min(total, available), height: CGFloat(rows.count) * rowH)
            NSGraphicsContext.saveGraphicsState()
            let outline = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
            outline.addClip()
            NSColor(MarginColor.sunken).setFill()
            NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: rowH).fill()
            NSColor(MarginColor.border).setStroke()
            for r in 1..<max(rows.count, 1) {
                let y = frame.minY + CGFloat(r) * rowH
                let p = NSBezierPath(); p.move(to: NSPoint(x: frame.minX, y: y)); p.line(to: NSPoint(x: frame.maxX, y: y)); p.lineWidth = 1; p.stroke()
            }
            var x = frame.minX
            for c in 0..<columns {
                if c > 0 {
                    NSColor(MarginColor.border).setStroke()
                    let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: frame.minY)); p.line(to: NSPoint(x: x, y: frame.maxY)); p.lineWidth = 1; p.stroke()
                }
                for (r, row) in rows.enumerated() where c < row.count {
                    let para = NSMutableParagraphStyle()
                    para.alignment = c < aligns.count ? aligns[c] : .left
                    para.lineBreakMode = .byTruncatingTail
                    let attrs: [NSAttributedString.Key: Any] = [.font: r == 0 ? bold : font, .foregroundColor: NSColor(MarginColor.ink), .paragraphStyle: para]
                    let cellRect = NSRect(x: x + 12, y: frame.minY + CGFloat(r) * rowH + (rowH - font.boundingRectForFont.height) / 2 + 1,
                                          width: widths[c] - 24, height: rowH)
                    (plain(row[c]) as NSString).draw(in: cellRect, withAttributes: attrs)
                }
                x += widths[c]
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor(MarginColor.border).setStroke()
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawTables(in: dirtyRect)
        for embed in embeds(in: dirtyRect) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: embed.rect, xRadius: 6, yRadius: 6).addClip()
            embed.image.draw(in: embed.rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(MarginColor.textTertiary).setFill()
        for dot in bullets(in: dirtyRect) { NSBezierPath(ovalIn: dot).fill() }
        for box in checkboxes(in: dirtyRect) {
            let path = NSBezierPath(roundedRect: box.rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            if box.checked {
                NSColor(MarginColor.accent).setFill()
                path.fill()
                let tick = NSBezierPath()
                let r = box.rect
                tick.move(to: NSPoint(x: r.minX + 4, y: r.midY))
                tick.line(to: NSPoint(x: r.minX + 7, y: r.midY + 3))
                tick.line(to: NSPoint(x: r.maxX - 4, y: r.midY - 3.5))
                tick.lineWidth = 1.8
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                NSColor.white.setFill()
                path.fill()
                NSColor(MarginColor.borderStrong).setStroke()
                path.lineWidth = 1.2
                path.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Checkbox: toggle `[ ]` ↔ `[x]` as an undoable edit, keeping the selection (M6-14).
        if let box = checkboxes(in: visibleRect).first(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(point) }) {
            let selection = selectedRange()
            replace(NSRange(location: box.char + 1, length: 1), with: box.checked ? " " : "x")
            setSelectedRange(selection)
            return
        }
        // Link: plain click in reading, ⌘-click while editing.
        if let target = link(at: point), !isEditable || event.modifierFlags.contains(.command) {
            coordinator?.parent.events.onOpenLink(target)
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndex(at: point)
        var kind: EditorContext.Kind = .plain
        let sel = selectedRange()
        if sel.length > 0, NSLocationInRange(index, sel) {
            kind = .selection((string as NSString).substring(with: sel))
        } else if let target = link(at: point) {
            kind = .link(target)
        } else if let storage = textStorage, index < storage.length {
            let text = string as NSString
            let line = text.lineRange(for: NSRange(location: index, length: 0))
            let content = text.substring(with: line)
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") {
                kind = .task(line: text.substring(to: line.location).components(separatedBy: "\n").count - 1)
            } else if trimmed.hasPrefix("#") {
                kind = .heading(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("![") {
                kind = .image
            } else if trimmed.hasPrefix("|") {
                kind = .table
            } else if let tag = Self.tag(in: text, at: index) {
                kind = .tag(tag)
            }
        }
        return coordinator?.parent.events.onContextMenu(EditorContext(kind: kind, location: index))
            ?? super.menu(for: event)
    }

    /// `#tag` under `index` (letters, digits, `_`, `-`, `/`), with its `#`.
    static func tag(in text: NSString, at index: Int) -> String? {
        func isTagChar(_ c: unichar) -> Bool {
            guard let u = UnicodeScalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(u) || c == 0x5F || c == 0x2D || c == 0x2F
        }
        var start = min(index, text.length - 1)
        guard start >= 0 else { return nil }
        while start > 0, isTagChar(text.character(at: start)) { start -= 1 }
        guard text.character(at: start) == 0x23, start == 0 || [0x20, 0x09, 0x0A].contains(text.character(at: start - 1)) else { return nil }
        var end = start + 1
        while end < text.length, isTagChar(text.character(at: end)) { end += 1 }
        guard end > start + 1 else { return nil }
        return text.substring(with: NSRange(location: start, length: end - start))
    }

    private func characterIndex(at point: NSPoint) -> Int {
        guard let layout = layoutManager, let container = textContainer else { return 0 }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: p, in: container)
        return layout.characterIndexForGlyph(at: glyph)
    }

    private func link(at point: NSPoint) -> String? {
        guard let storage = textStorage, storage.length > 0, let layout = layoutManager,
              let container = textContainer else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: p, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let bounds = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard bounds.insetBy(dx: -2, dy: -2).contains(p) else { return nil }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return nil }
        return storage.attribute(.marginWikilink, at: index, effectiveRange: nil) as? String
    }

    // MARK: Hover (link preview, pointer)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        hoverTracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let target = link(at: point)
        if checkboxes(in: visibleRect).contains(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(point) }) || target != nil {
            NSCursor.pointingHand.set()
        }
        if target != hoveredLink {
            hoveredLink = target
            coordinator?.parent.events.onHoverLink(target, NSRect(origin: event.locationInWindow, size: .zero))
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if hoveredLink != nil {
            hoveredLink = nil
            coordinator?.parent.events.onHoverLink(nil, .zero)
        }
    }
}
