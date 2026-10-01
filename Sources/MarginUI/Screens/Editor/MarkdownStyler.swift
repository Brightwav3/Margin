import AppKit
import MarginCore
import SwiftUI


/// Editor modes of 3a: live (syntax hidden outside the block under the cursor), source (all
/// Markdown, monospace) and reading (rendered, not editable).
public enum EditorMode: String, Sendable, CaseIterable {
    case live, source, reading
}

extension NSAttributedString.Key {
    /// Characters laid out as nothing (live and reading hide Markdown syntax this way).
    static let marginHidden = NSAttributedString.Key("margin.hidden")
    /// `[ ]` / `[x]` of a task drawn as a checkbox; the value is `true` when checked.
    static let marginCheckbox = NSAttributedString.Key("margin.checkbox")
    /// Target note title of a `[[wikilink]]` (click opens it, hover previews it).
    static let marginWikilink = NSAttributedString.Key("margin.wikilink")
    /// The source of a Markdown table, on its first line; the text view draws it as a grid
    /// while the table is not being edited.
    static let marginTable = NSAttributedString.Key("margin.table")
    /// An embedded image `![[name.png|200]]`: the value is `name|spec`; the text view draws the
    /// picture in the line the styler made tall enough.
    static let marginEmbed = NSAttributedString.Key("margin.embed")
    /// `-`, `*` or `+` of a list item drawn as a round bullet (live and reading, like Obsidian).
    static let marginBullet = NSAttributedString.Key("margin.bullet")
}

/// Turns `MarkdownTokenizer` tokens into text attributes (M6-02.U). Pure and range-based, so the
/// editor restyles only the lines an edit touched and the blocks the cursor entered or left.
@MainActor
enum MarkdownStyler {
    static let ink = NSColor(MarginColor.ink)
    static let secondary = NSColor(MarginColor.textSecondary)
    static let tertiary = NSColor(MarginColor.textTertiary)
    /// Dimmed syntax in the active block (`##` in the live mockup).
    static let dim = NSColor(MarginColor.textDisabled)
    static let accent = NSColor(MarginColor.accent)
    static let key = NSColor(MarginColor.accentText)
    static let sunken = NSColor(MarginColor.sunken)
    static let due = NSColor(MarginColor.due)
    static let dueSoft = NSColor(MarginColor.dueSoft)

    /// Body text of live and reading: 17 px, line height 1.6.
    static let bodySize: CGFloat = 17
    /// Source: monospace 14, line height 1.75.
    static let sourceSize: CGFloat = 14

    /// View › Zoom in / out: scales every editor size (1 = actual size).
    static var scale: CGFloat = 1

    static func bodyFont(_ weight: NSFont.Weight = .regular, size: CGFloat = bodySize) -> NSFont {
        let size = size * scale
        let w: Font.Weight = switch weight {
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
        return MarginFonts.nsFont(size: size, weight: w)
    }

    /// Yellow of `==highlight==` (Obsidian's text highlight).
    static let highlightFill = NSColor(srgbRed: 1, green: 0.91, blue: 0.4, alpha: 0.45)

    /// Serif italic for formulas, until real TeX rendering.
    static func mathFont(size: CGFloat) -> NSFont {
        let base = NSFont(name: "STIXTwoMath-Regular", size: size * scale) ?? NSFont(name: "Times New Roman", size: size * scale)
            ?? .systemFont(ofSize: size * scale)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    static func mono(_ size: CGFloat = sourceSize, bold: Bool = false) -> NSFont {
        let size = size * scale
        return NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    static func paragraph(lineHeight: CGFloat, size: CGFloat, spacing: CGFloat = 0) -> NSParagraphStyle {
        let size = size * scale
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = (size * lineHeight).rounded()
        p.maximumLineHeight = (size * lineHeight).rounded()
        p.paragraphSpacing = spacing
        return p
    }

    static func baseAttributes(_ mode: EditorMode) -> [NSAttributedString.Key: Any] {
        switch mode {
        case .source:
            [.font: mono(), .foregroundColor: ink, .paragraphStyle: paragraph(lineHeight: 1.75, size: sourceSize),
             .kern: 0]
        case .live, .reading:
            [.font: bodyFont(), .foregroundColor: ink, .paragraphStyle: paragraph(lineHeight: 1.6, size: bodySize, spacing: 4),
             .kern: -0.2]
        }
    }

    /// Restyles `range` of `storage` (UTF-16). `active` is the block under the cursor in live mode.
    static func apply(to storage: NSTextStorage, range: NSRange, tokens: [MarkdownToken], mode: EditorMode,
                      active: MarkdownRange?) {
        let full = NSRange(location: 0, length: storage.length)
        let range = NSIntersectionRange(range, full)
        guard range.length > 0 || storage.length == 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(baseAttributes(mode), range: range)
        let text = storage.string as NSString
        if mode != .source { compactBlankLines(storage, text, range) }
        for token in tokens {
            let r = NSRange(location: token.range.location, length: token.range.length)
            guard r.location >= range.location, NSMaxRange(r) <= NSMaxRange(range), r.length > 0 else {
                // A token reaching outside the restyled range is applied where it overlaps.
                let overlap = NSIntersectionRange(r, range)
                if overlap.length > 0 {
                    style(token.kind, overlap, storage, text, mode, isActive(r, active))
                }
                continue
            }
            style(token.kind, r, storage, text, mode, isActive(r, active))
        }
        if mode != .source { tables(storage, text, range, tokens: tokens, active: mode == .live ? active : nil) }
    }

    /// Height of a table row drawn as a grid.
    static var tableRowHeight: CGFloat { 34 * scale }

    /// Tables outside the block being edited: their lines are hidden and the first one is as tall
    /// as the drawn grid (`MarginTextView` draws it from `.marginTable`).
    private static func tables(_ s: NSTextStorage, _ text: NSString, _ range: NSRange, tokens: [MarkdownToken], active: MarkdownRange?) {
        var lines: [NSRange] = []
        func flush() {
            defer { lines.removeAll() }
            guard lines.count >= 2, let first = lines.first, let last = lines.last else { return }
            let block = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            if let active, NSIntersectionRange(block, NSRange(location: active.location, length: max(active.length, 1))).length > 0 { return }
            let source = text.substring(with: block)
            let rows = source.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .filter { !TableEditing.isDelimiter(TableEditing.cells($0)) }
            let height = CGFloat(rows.count) * tableRowHeight + 12
            for (i, line) in lines.enumerated() {
                let full = text.lineRange(for: line)
                var content = full
                if content.length > 0, text.character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
                s.addAttribute(.marginHidden, value: true, range: content)
                let p = NSMutableParagraphStyle()
                p.minimumLineHeight = i == 0 ? height : 0.01
                p.maximumLineHeight = i == 0 ? height : 0.01
                s.addAttribute(.paragraphStyle, value: p, range: full)
            }
            s.addAttribute(.marginTable, value: source, range: NSRange(location: first.location, length: 1))
        }
        var lastEnd = -1
        for t in tokens {
            switch t.kind {
            case .tableRow, .tableDelimiterRow:
                let line = text.lineRange(for: NSRange(location: t.range.location, length: 0))
                if lines.last == line { continue }
                if lastEnd >= 0, line.location != lastEnd { flush() }
                lines.append(line)
                lastEnd = NSMaxRange(line)
            default: continue
            }
        }
        flush()
    }

    private static func isActive(_ r: NSRange, _ active: MarkdownRange?) -> Bool {
        guard let active else { return false }
        let a = NSRange(location: active.location, length: max(active.length, 1))
        return NSIntersectionRange(r, a).length > 0 || (r.location >= a.location && r.location <= NSMaxRange(a))
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func style(_ kind: MarkdownTokenKind, _ r: NSRange, _ s: NSTextStorage, _ text: NSString,
                              _ mode: EditorMode, _ active: Bool) {
        let source = mode == .source
        /// Syntax characters: grey in source, dimmed in the active block, hidden elsewhere.
        func marker(_ range: NSRange = r) {
            if source { s.addAttribute(.foregroundColor, value: tertiary, range: range) }
            else if active && mode == .live { s.addAttribute(.foregroundColor, value: dim, range: range) }
            else { s.addAttribute(.marginHidden, value: true, range: range) }
        }
        switch kind {
        case .frontmatterDelimiter:
            if source { s.addAttribute(.foregroundColor, value: tertiary, range: r) } else { hideLine(r, s, text) }
        case .frontmatter:
            if source {
                // `key:` in blue, list dashes grey.
                let line = text.substring(with: r)
                if let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") {
                    let len = line.distance(from: line.startIndex, to: colon) + 1
                    s.addAttribute(.foregroundColor, value: key, range: NSRange(location: r.location, length: len))
                } else if let dash = line.firstIndex(of: "-") {
                    let at = line.utf16.distance(from: line.utf16.startIndex, to: dash.samePosition(in: line.utf16)!)
                    s.addAttribute(.foregroundColor, value: tertiary, range: NSRange(location: r.location + at, length: 1))
                }
            } else {
                hideLine(r, s, text)
            }
        case .headingMarker:
            marker(NSRange(location: r.location, length: r.length))
            if !source && !(active && mode == .live) { hideTrailingSpace(after: r, s, text) }
        case .headingText(let level):
            if source {
                s.addAttribute(.font, value: mono(sourceSize, bold: true), range: r)
            } else {
                let (size, weight, tracking, space): (CGFloat, NSFont.Weight, CGFloat, CGFloat) = switch level {
                case 1: (30, .bold, -0.6, 14)
                case 2: (20, .semibold, -0.3, 10)
                case 3: (17, .semibold, -0.2, 8)
                default: (15, .semibold, -0.2, 6)
                }
                let line = text.lineRange(for: r)
                s.addAttribute(.font, value: bodyFont(weight, size: size), range: line)
                s.addAttribute(.kern, value: tracking, range: r)
                let p = paragraph(lineHeight: level == 1 ? 1.3 : 1.45, size: size, spacing: space)
                let m = p.mutableCopy() as! NSMutableParagraphStyle
                // More room above a heading than below it, so it belongs to what follows (Obsidian).
                m.paragraphSpacingBefore = switch level { case 1: 22; case 2: 18; case 3: 14; default: 10 }
                m.paragraphSpacing = 4
                s.addAttribute(.paragraphStyle, value: m, range: line)
            }
        case .listBullet, .listOrdered:
            s.addAttribute(.foregroundColor, value: tertiary, range: r)
            guard !source else { break }
            listLine(r, s, text, ordered: kind == .listOrdered)
            if kind == .listBullet {
                let after = NSMaxRange(r) + 1
                let isTask = after + 2 < text.length && text.substring(with: NSRange(location: after, length: 1)) == "["
                if isTask {
                    // A task shows its checkbox only, as in Obsidian.
                    s.addAttribute(.foregroundColor, value: active && mode == .live ? dim : NSColor.clear, range: r)
                } else if !(active && mode == .live) {
                    s.addAttributes([.foregroundColor: NSColor.clear, .marginBullet: true], range: r)
                }
            }
        case .taskCheckbox(let checked):
            if source {
                s.addAttribute(.foregroundColor, value: tertiary, range: r)
            } else if active && mode == .live {
                s.addAttribute(.foregroundColor, value: dim, range: r)
            } else {
                // Drawn by the text view as a checkbox over invisible brackets.
                s.addAttributes([.foregroundColor: NSColor.clear, .marginCheckbox: checked], range: r)
            }
            if checked && !source {
                let line = text.lineRange(for: r)
                let rest = NSRange(location: NSMaxRange(r), length: max(0, NSMaxRange(line) - NSMaxRange(r)))
                s.addAttributes([.foregroundColor: tertiary, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                 .strikethroughColor: tertiary], range: rest)
            }
        case .blockquoteMarker:
            marker()
            if !source { s.addAttribute(.foregroundColor, value: secondary, range: text.lineRange(for: r)) }
        case .callout:
            s.addAttribute(.foregroundColor, value: accent, range: r)
        case .codeFenceMarker, .codeInfo:
            if source { s.addAttribute(.foregroundColor, value: tertiary, range: r) }
            else if active && mode == .live { s.addAttributes([.foregroundColor: dim, .font: mono(15)], range: r) }
            else { hideLine(r, s, text) }
        case .codeLine, .indentedCodeLine:
            s.addAttributes([.font: mono(source ? sourceSize : 15), .backgroundColor: sunken], range: r)
        case .inlineCode:
            s.addAttributes([.font: mono(source ? sourceSize : 15), .backgroundColor: sunken], range: r)
            if !source && r.length >= 2 {
                marker(NSRange(location: r.location, length: 1))
                marker(NSRange(location: NSMaxRange(r) - 1, length: 1))
            }
        case .emphasis:
            s.applyFontTraits(.italicFontMask, range: r)
            if !source { delimiters(r, 1, marker) }
        case .strong:
            s.addAttribute(.font, value: source ? mono(sourceSize, bold: true) : bodyFont(.semibold), range: r)
            if !source { delimiters(r, 2, marker) }
        case .strikethrough:
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            if !source { delimiters(r, 2, marker) }
        case .wikilink(let embed):
            s.addAttribute(.foregroundColor, value: accent, range: r)
            if embed, !source, !(active && mode == .live), embedImage(r, s, text) { break }
            if !source {
                let open = embed ? 3 : 2
                marker(NSRange(location: r.location, length: min(open, r.length)))
                marker(NSRange(location: NSMaxRange(r) - min(2, r.length), length: min(2, r.length)))
                let inner = text.substring(with: NSRange(location: r.location + open, length: max(0, r.length - open - 2)))
                let target = inner.split(separator: "|").first.map { String($0).split(separator: "#").first.map(String.init) ?? "" } ?? inner
                s.addAttribute(.marginWikilink, value: target, range: r)
                // `[[target|alias]]`: outside the active block only the alias shows.
                if let pipe = (inner as NSString).range(of: "|").location as Int?, pipe != NSNotFound {
                    marker(NSRange(location: r.location + open, length: pipe + 1))
                }
                s.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue,
                                 .underlineColor: accent.withAlphaComponent(0.4)], range: r)
            }
        case .wikilinkTarget, .wikilinkHeading:
            break
        case .wikilinkAlias:
            break
        case .link:
            s.addAttribute(.foregroundColor, value: accent, range: r)
        case .linkText:
            s.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                             .underlineColor: accent.withAlphaComponent(0.4)], range: r)
            if !source {
                // `[` before and `](…)` after the text.
                marker(NSRange(location: r.location - 1, length: 1))
            }
        case .linkDestination:
            if !source {
                marker(NSRange(location: r.location - 2, length: r.length + 3))
            } else {
                s.addAttribute(.foregroundColor, value: tertiary, range: r)
            }
        case .tag:
            s.addAttribute(.foregroundColor, value: accent, range: r)
        case .due:
            if source {
                s.addAttribute(.foregroundColor, value: key, range: r)
            } else {
                s.addAttributes([.foregroundColor: secondary, .backgroundColor: sunken,
                                 .font: bodyFont(size: 14)], range: r)
            }
        case .blockID:
            marker()
        case .tableRow(let header):
            s.addAttribute(.font, value: mono(source ? sourceSize : 15, bold: header), range: r)
        case .tableDelimiterRow:
            s.addAttributes([.font: mono(source ? sourceSize : 15), .foregroundColor: tertiary], range: r)
        case .horizontalRule:
            s.addAttributes([.foregroundColor: tertiary, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .strikethroughColor: NSColor(MarginColor.border)], range: r)
        case .highlight:
            s.addAttribute(.backgroundColor, value: highlightFill, range: r)
            if !source { delimiters(r, 2, marker) }
        case .comment, .commentLine:
            // Visible while editing, grey; gone in reading view (Obsidian).
            if mode == .reading { hideLine(r, s, text) } else {
                s.addAttribute(.foregroundColor, value: tertiary, range: r)
                if kind == .comment, !source { s.addAttribute(.foregroundColor, value: dim, range: NSRange(location: r.location, length: 2)) }
            }
        case .commentFence:
            if mode == .reading { hideLine(r, s, text) } else { s.addAttribute(.foregroundColor, value: dim, range: r) }
        case .inlineMath:
            s.addAttributes([.font: mathFont(size: bodySize), .foregroundColor: ink], range: r)
            if !source && r.length >= 2 {
                marker(NSRange(location: r.location, length: 1))
                marker(NSRange(location: NSMaxRange(r) - 1, length: 1))
            }
        case .mathFence:
            if source { s.addAttribute(.foregroundColor, value: tertiary, range: r) }
            else if active && mode == .live { s.addAttribute(.foregroundColor, value: dim, range: r) }
            else { hideLine(r, s, text) }
        case .mathLine:
            if source { s.addAttribute(.font, value: mono(), range: r) } else {
                let p = paragraph(lineHeight: 1.6, size: bodySize).mutableCopy() as! NSMutableParagraphStyle
                p.alignment = .center
                s.addAttributes([.font: mathFont(size: bodySize + 1), .paragraphStyle: p], range: text.lineRange(for: r))
            }
        case .escape:
            if !source { marker(NSRange(location: r.location, length: 1)) }
        case .footnoteRef(let definition):
            if definition {
                s.addAttributes([.foregroundColor: tertiary, .font: bodyFont(.medium, size: 14)], range: r)
            } else {
                s.addAttributes([.foregroundColor: tertiary, .font: bodyFont(.medium, size: 12), .baselineOffset: 6 * scale], range: r)
            }
        case .inlineFootnote:
            s.addAttributes([.foregroundColor: tertiary, .font: bodyFont(size: 14)], range: r)
        }
    }

    /// Widest an embedded image is drawn (the readable column).
    static var maxEmbedWidth: CGFloat { 640 * scale }

    /// `![[picture.png]]` outside the block being edited: the text is hidden and its line is as tall
    /// as the picture. Returns false for embeds that are not pictures (they stay links).
    private static func embedImage(_ r: NSRange, _ s: NSTextStorage, _ text: NSString) -> Bool {
        let inner = text.substring(with: NSRange(location: r.location + 3, length: max(0, r.length - 5)))
        let parts = inner.split(separator: "|", maxSplits: 1).map { String($0).replacingOccurrences(of: "\\", with: "") }
        guard let name = parts.first?.trimmingCharacters(in: .whitespaces), EmbedImages.isImage(name) else { return false }
        let spec = parts.count > 1 ? parts[1] : nil
        let image = EmbedImages.shared.image(name)
        if image == nil && EmbedImages.shared.didFail(name) { return false }
        let size = image.map { EmbedImages.displaySize(of: $0, spec: spec, maxWidth: maxEmbedWidth) } ?? NSSize(width: 0, height: 24)
        s.addAttributes([.marginHidden: true, .marginEmbed: name + "|" + (spec ?? "")], range: r)
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = size.height + 12
        p.maximumLineHeight = size.height + 12
        s.addAttribute(.paragraphStyle, value: p, range: text.lineRange(for: r))
        return true
    }

    /// A list line: tight spacing and a hanging indent, so wrapped lines start under the text, not
    /// under the bullet; nested items step in by their indentation.
    private static func listLine(_ marker: NSRange, _ s: NSTextStorage, _ text: NSString, ordered: Bool) {
        let line = text.lineRange(for: marker)
        let content = text.substring(with: line)
        let font = bodyFont()
        let width = { (str: String) in (str as NSString).size(withAttributes: [.font: font]).width }
        var prefixEnd = NSMaxRange(marker) - line.location
        let rest = (content as NSString).substring(from: min(prefixEnd, (content as NSString).length))
        if rest.hasPrefix(" [ ] ") || rest.hasPrefix(" [x] ") || rest.hasPrefix(" [X] ") { prefixEnd += 5 } else if rest.hasPrefix(" ") { prefixEnd += 1 }
        let prefix = (content as NSString).substring(to: min(prefixEnd, (content as NSString).length))
        let p = paragraph(lineHeight: 1.6, size: bodySize, spacing: 1).mutableCopy() as! NSMutableParagraphStyle
        p.defaultTabInterval = 26 * scale
        p.tabStops = []
        p.headIndent = width(prefix.replacingOccurrences(of: "\t", with: "    "))
        s.addAttribute(.paragraphStyle, value: p, range: line)
    }

    /// Blank lines between blocks are short in live and reading (the mockup's block margins), full in source.
    private static func compactBlankLines(_ s: NSTextStorage, _ text: NSString, _ range: NSRange) {
        var location = text.lineRange(for: NSRange(location: range.location, length: 0)).location
        let end = NSMaxRange(range)
        let blank = paragraph(lineHeight: 1, size: 10)
        while location < end && location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let content = text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                s.addAttributes([.paragraphStyle: blank, .font: bodyFont(size: 8)], range: line)
            }
            location = NSMaxRange(line)
        }
    }

    private static func delimiters(_ r: NSRange, _ n: Int, _ marker: (NSRange) -> Void) {
        guard r.length > 2 * n else { return }
        marker(NSRange(location: r.location, length: n))
        marker(NSRange(location: NSMaxRange(r) - n, length: n))
    }

    private static func hideLine(_ r: NSRange, _ s: NSTextStorage, _ text: NSString) {
        s.addAttribute(.marginHidden, value: true, range: text.lineRange(for: r))
    }

    private static func hideTrailingSpace(after r: NSRange, _ s: NSTextStorage, _ text: NSString) {
        let next = NSMaxRange(r)
        if next < text.length, text.character(at: next) == 0x20 {
            s.addAttribute(.marginHidden, value: true, range: NSRange(location: next, length: 1))
        }
    }
}
