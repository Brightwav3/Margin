import AppKit
import MarginCore

/// Block types of Format (paragraph, headings, quote, lists).
public enum EditorBlock: String, CaseIterable, Sendable {
    case paragraph, heading1, heading2, heading3, quote, bullets, numbers, checklist
}

/// Text styles of Format and the selection toolbar.
public enum EditorInline: String, CaseIterable, Sendable {
    case bold, italic, underline, strike, highlight, code

    var marks: (String, String) {
            switch self {
            case .bold: ("**", "**")
            case .italic: ("*", "*")
            case .underline: ("<u>", "</u>")
            case .strike: ("~~", "~~")
        case .highlight: ("==", "==")
        case .code: ("`", "`")
        }
    }
}

/// Blocks of Insert.
public enum EditorInsertion: String, CaseIterable, Sendable {
    case link, task, table, formula, date, callout, code, footnote, divider
}

/// Insert and Format commands of the menu bar (M10-35), applied to the text view as one undoable edit.
@MainActor
extension EditorHandle {
    var isAvailable: Bool { textView?.isEditable == true }

    /// Wraps the selection (or the word at the caret) in the style's marks; unwraps when already styled.
    func toggle(_ style: EditorInline) {
        guard let tv = textView else { return }
        let (open, close) = style.marks
        var range = tv.selectedRange()
        let text = tv.string as NSString
        if range.length == 0 { range = wordRange(at: range.location, in: text) }
        let selected = text.substring(with: range)
        if selected.hasPrefix(open), selected.hasSuffix(close), selected.count >= open.count + close.count {
            let inner = String(selected.dropFirst(open.count).dropLast(close.count))
            tv.replace(range, with: inner)
            tv.setSelectedRange(NSRange(location: range.location, length: (inner as NSString).length))
            return
        }
        // Marks just outside the selection: remove them.
        let before = NSRange(location: range.location - (open as NSString).length, length: (open as NSString).length)
        let after = NSRange(location: NSMaxRange(range), length: (close as NSString).length)
        if before.location >= 0, NSMaxRange(after) <= text.length,
           text.substring(with: before) == open, text.substring(with: after) == close {
            tv.replace(NSRange(location: before.location, length: NSMaxRange(after) - before.location), with: selected)
            tv.setSelectedRange(NSRange(location: before.location, length: range.length))
            return
        }
        tv.replace(range, with: open + selected + close)
        tv.setSelectedRange(NSRange(location: range.location + (open as NSString).length, length: range.length))
    }

    /// Sets the block type of every selected line (heading, quote, list, checklist, paragraph).
    func setBlock(_ block: EditorBlock) {
        editLines { line, index in
            let body = Self.stripBlockPrefix(line)
            switch block {
            case .paragraph: return body.text
            case .heading1: return body.indent + "# " + body.content
            case .heading2: return body.indent + "## " + body.content
            case .heading3: return body.indent + "### " + body.content
            case .quote: return body.indent + "> " + body.content
            case .bullets: return body.indent + "- " + body.content
            case .numbers: return body.indent + "\(index + 1). " + body.content
            case .checklist: return body.indent + "- [ ] " + body.content
            }
        }
    }

    func indent() { editLines { line, _ in "\t" + line } }

    func outdent() {
        editLines { line, _ in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix { $0 == " " }.count
            return String(line.dropFirst(min(spaces, 4)))
        }
    }

    /// Removes inline marks (`**`, `*`, `~~`, `==`, `` ` ``, `<u>`) and block prefixes from the selection.
    func clearFormatting() {
        guard let tv = textView else { return }
        let range = lineRange(tv)
        var text = (tv.string as NSString).substring(with: range)
        for mark in ["**", "~~", "==", "<u>", "</u>", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(?!\s)([^*\n]+)(?<!\s)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        let lines = text.components(separatedBy: "\n").map { Self.stripBlockPrefix($0).text }
        tv.replace(range, with: lines.joined(separator: "\n"))
    }

    // MARK: Insert

    func insert(_ what: EditorInsertion, clock: any Clock) {
        guard let tv = textView else { return }
        let caret = tv.selectedRange()
        let atLineStart = caret.location == 0 || (tv.string as NSString).character(at: caret.location - 1) == 0x0A
        let nl = atLineStart ? "" : "\n"
        let (text, caretOffset): (String, Int) = switch what {
        case .link: ("[[]]", 2)
        case .task: ("\(nl)- [ ] ", -1)
        case .table: ("\(nl)| Column | Column |\n| --- | --- |\n|  |  |\n", -1)
        case .formula: ("\(nl)$$\n\n$$\n", (nl + "$$\n").utf16.count)
        case .date: ("\(clock.today.iso) \(clock.localNow.time.string)", -1)
        case .callout: ("\(nl)> [!note]\n> ", -1)
        case .code: ("\(nl)```\n\n```\n", (nl + "```\n").utf16.count)
        case .footnote: ("[^1]", -1)
        case .divider: ("\(nl)\n---\n\n", -1)
        }
        tv.replace(caret, with: text)
        if caretOffset >= 0 { tv.setSelectedRange(NSRange(location: caret.location + caretOffset, length: 0)) }
    }

    // MARK: Clipboard and find

    /// Copies the selection as its Markdown source (the text view holds Markdown, so as is).
    func copyAsMarkdown() {
        guard let tv = textView else { return }
        let s = (tv.string as NSString).substring(with: tv.selectedRange())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func pasteAsPlainText() { textView?.pasteAsPlainText(nil) }

    func find(replace: Bool) {
        focus()
        let item = NSMenuItem()
        item.tag = (replace ? NSTextFinder.Action.showReplaceInterface : .showFindInterface).rawValue
        textView?.performTextFinderAction(item)
    }

    // MARK: Helpers

    private func lineRange(_ tv: NSTextView) -> NSRange {
        let text = tv.string as NSString
        var r = text.lineRange(for: tv.selectedRange())
        if r.length > 0, NSMaxRange(r) <= text.length, text.character(at: NSMaxRange(r) - 1) == 0x0A { r.length -= 1 }
        return r
    }

    private func editLines(_ transform: (String, Int) -> String) {
        guard let tv = textView else { return }
        let range = lineRange(tv)
        let lines = (tv.string as NSString).substring(with: range).components(separatedBy: "\n")
        let out = lines.enumerated().map { transform($0.element, $0.offset) }.joined(separator: "\n")
        tv.replace(range, with: out)
        tv.setSelectedRange(NSRange(location: range.location, length: (out as NSString).length))
    }

    private func wordRange(at location: Int, in text: NSString) -> NSRange {
        var start = location, end = location
        let letters = CharacterSet.alphanumerics
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < text.length, let u = UnicodeScalar(text.character(at: i)) else { return false }
            return letters.contains(u)
        }
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Splits `line` into its indent, block prefix and content.
    nonisolated static func stripBlockPrefix(_ line: String) -> (indent: String, content: String, text: String) {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        var rest = Substring(line.dropFirst(indent.count))
        let patterns = [#"^#{1,6} "#, #"^> "#, #"^[-*+] \[[ xX]\] "#, #"^[-*+] "#, #"^\d+[.)] "#]
        for p in patterns {
            if let r = rest.range(of: p, options: .regularExpression) { rest = rest[r.upperBound...]; break }
        }
        return (indent, String(rest), indent + rest)
    }
}
