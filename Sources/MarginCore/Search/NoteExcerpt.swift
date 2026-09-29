import Foundation

/// The hover preview of a note or of one of its sections (M10-05): plain text, short.
public struct NoteExcerpt: Codable, Sendable, Hashable {
    /// Plain text: no frontmatter, no markdown markers. Empty for a note without prose.
    public var text: String
    /// The heading the excerpt was taken from; `nil` for the start of the note (also when the
    /// requested heading does not exist).
    public var heading: String?
    /// `true` when the paragraph was cut to fit the length limit (`text` then ends with `…`).
    public var isTruncated: Bool

    public var isEmpty: Bool { text.isEmpty }

    public init(text: String, heading: String? = nil, isTruncated: Bool = false) {
        self.text = text; self.heading = heading; self.isTruncated = isTruncated
    }
}

/// Builds `NoteExcerpt`s from note text.
///
/// - The text may still contain frontmatter; it is skipped.
/// - Without `heading`: the first block of prose. Headings at the top (the title), horizontal
///   rules, fenced code, `%%comments%%` and blank lines are skipped; a paragraph, list or quote
///   counts as a block.
/// - With `heading` (case and diacritics ignored): the first block of prose in that section, which
///   ends at the next heading of the same or a higher level. A missing heading falls back to the
///   start of the note (`NoteExcerpt.heading == nil`); an empty section gives an empty excerpt.
/// - Inline markdown is reduced to its text: `[[Note|alias]]` -> `alias`, `[[Note]]` -> `Note`,
///   `[t](url)` -> `t`, embeds and block ids are dropped, `**`, `*`, `~~`, `==` and backticks
///   removed. List items become `• item` lines.
/// - `maxLength` counts characters; longer text is cut at a word boundary and ends with `…`.
public enum NoteExcerptProvider {
    public static let defaultMaxLength = 280

    public static func excerpt(of text: String, heading: String? = nil, maxLength: Int = defaultMaxLength) -> NoteExcerpt {
        let body = Frontmatter.parse(text.contains("\r") ? text.replacingOccurrences(of: "\r\n", with: "\n") : text).body
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : String($0)
        }
        var start = 0
        var end = lines.count
        var resolved: String?

        if let wanted = heading.map({ SearchTokenizer.fold($0).trimmingCharacters(in: .whitespaces) }), !wanted.isEmpty {
            var inFence = false
            for (i, line) in lines.enumerated() {
                if isFence(line) { inFence.toggle(); continue }
                guard !inFence, let h = atxHeading(line), SearchTokenizer.fold(h.text).trimmingCharacters(in: .whitespaces) == wanted
                else { continue }
                resolved = h.text
                start = i + 1
                end = sectionEnd(lines, after: i, level: h.level)
                break
            }
        }

        // A block that is only embeds (an image) has no text; the next block is the excerpt.
        var clean = ""
        var position = start
        while clean.isEmpty, let (block, next) = firstBlock(lines, from: position, to: end) {
            clean = cleanBlock(block)
            position = next
        }
        let (cut, truncated) = limit(clean, to: maxLength)
        return NoteExcerpt(text: cut, heading: resolved, isTruncated: truncated)
    }

    // MARK: Blocks

    private static func sectionEnd(_ lines: [String], after index: Int, level: Int) -> Int {
        var inFence = false
        for i in (index + 1)..<max(index + 1, lines.count) {
            if isFence(lines[i]) { inFence.toggle(); continue }
            if !inFence, let h = atxHeading(lines[i]), h.level <= level { return i }
        }
        return lines.count
    }

    /// The lines of the first prose block in `lines[from..<to]` and the index after it.
    private static func firstBlock(_ lines: [String], from: Int, to: Int) -> (block: [String], next: Int)? {
        var block: [String] = []
        var inFence = false
        var inComment = false
        var i = from
        while i < to {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            i += 1
            if inComment {
                if t.contains("%%") { inComment = false }
                continue
            }
            if isFence(line) { inFence.toggle(); if !block.isEmpty { break }; continue }
            if inFence { continue }
            if t.hasPrefix("%%") {
                // `%%` on its own line opens a multi-line comment unless it closes on the same line.
                if t.dropFirst(2).contains("%%") { continue }
                inComment = true
                continue
            }
            if t.isEmpty { if block.isEmpty { continue } else { break } }
            if atxHeading(line) != nil { if block.isEmpty { continue } else { break } }
            if isRule(t) { if block.isEmpty { continue } else { break } }
            block.append(t)
        }
        return block.isEmpty ? nil : (block, i)
    }

    private static func isFence(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("```") || t.hasPrefix("~~~")
    }

    private static func isRule(_ t: String) -> Bool {
        guard t.count >= 3, let c = t.first, "-*_".contains(c) else { return false }
        return t.allSatisfy { $0 == c || $0 == " " }
    }

    static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var idx = line.startIndex
        // Up to three spaces of indentation, then 1...6 `#`, then a space or the end.
        var spaces = 0
        while idx < line.endIndex, line[idx] == " ", spaces < 3 { idx = line.index(after: idx); spaces += 1 }
        while idx < line.endIndex, line[idx] == "#" { level += 1; idx = line.index(after: idx) }
        guard (1...6).contains(level), idx == line.endIndex || line[idx] == " " || line[idx] == "\t" else { return nil }
        var text = line[idx...].trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    // MARK: Cleaning

    private static func cleanBlock(_ block: [String]) -> String {
        let isList = block.allSatisfy { listItem($0) != nil }
        var lines: [String] = []
        for raw in block {
            var t = raw
            if t.hasPrefix(">") { t = String(t.drop(while: { $0 == ">" || $0 == " " })) }
            if let item = listItem(t) { t = "• " + item }
            lines.append(cleanInline(t))
        }
        let joined = isList ? lines.joined(separator: "\n") : lines.joined(separator: " ")
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text of a list item (`- x`, `* x`, `+ x`, `1. x`, task boxes removed), or `nil`.
    private static func listItem(_ line: String) -> String? {
        var t = Substring(line.trimmingCharacters(in: .whitespaces))
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
            t = t.dropFirst(2)
        } else {
            let digits = t.prefix(while: { $0.isNumber })
            let rest = t.dropFirst(digits.count)
            guard !digits.isEmpty, digits.count <= 9, rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
            t = rest.dropFirst(2)
        }
        for box in ["[ ] ", "[x] ", "[X] "] where t.hasPrefix(box) { t = t.dropFirst(box.count); break }
        return String(t)
    }

    private static func cleanInline(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let rest = s[i...]
            if rest.hasPrefix("![["), let close = rest.range(of: "]]") {          // embed: dropped
                i = close.upperBound; continue
            }
            if rest.hasPrefix("[["), let close = rest.range(of: "]]") {
                let inner = rest[rest.index(rest.startIndex, offsetBy: 2)..<close.lowerBound]
                if let bar = inner.firstIndex(of: "|") { out += inner[inner.index(after: bar)...] }
                else { out += inner.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first(where: { !$0.isEmpty }) ?? inner }
                i = close.upperBound; continue
            }
            if rest.hasPrefix("!["), let m = markdownLink(rest.dropFirst()) { i = m.end; continue }   // image: dropped
            if rest.hasPrefix("["), let m = markdownLink(rest) { out += m.text; i = m.end; continue }
            if rest.hasPrefix("**") || rest.hasPrefix("~~") || rest.hasPrefix("==") || rest.hasPrefix("__") {
                i = s.index(i, offsetBy: 2); continue
            }
            let c = s[i]
            if c == "*" || c == "`" { i = s.index(after: i); continue }
            out.append(c)
            i = s.index(after: i)
        }
        // A trailing block id (`^abc123`) is not text.
        if let caret = out.range(of: " ^", options: .backwards),
           out[caret.upperBound...].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }), !out[caret.upperBound...].isEmpty {
            out.removeSubrange(caret.lowerBound...)
        }
        return out
    }

    /// `[text](url)` at the start of `s`: the text and the index after the closing parenthesis.
    private static func markdownLink(_ s: Substring) -> (text: String, end: String.Index)? {
        guard s.first == "[", let closeBracket = s.firstIndex(of: "]") else { return nil }
        let afterBracket = s.index(after: closeBracket)
        guard afterBracket < s.endIndex, s[afterBracket] == "(", let closeParen = s[afterBracket...].firstIndex(of: ")")
        else { return nil }
        return (String(s[s.index(after: s.startIndex)..<closeBracket]), s.index(after: closeParen))
    }

    private static func limit(_ text: String, to maxLength: Int) -> (String, Bool) {
        let n = max(0, maxLength)
        guard text.count > n else { return (text, false) }
        guard n > 0 else { return ("", true) }
        var cut = String(text.prefix(n))
        // Back up to a word boundary unless that would throw away most of the text.
        if let space = cut.lastIndex(where: { $0 == " " || $0 == "\n" }), cut.distance(from: cut.startIndex, to: space) > n / 2 {
            cut = String(cut[..<space])
        }
        cut = cut.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = cut.last, ",;:-–".contains(last) { cut.removeLast() }
        return (cut + "…", true)
    }
}
