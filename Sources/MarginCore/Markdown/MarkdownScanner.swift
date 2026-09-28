/// Half-open range of UTF-8 byte offsets into the scanned text (`start ..< end`).
///
/// Offsets are UTF-8 (not UTF-16) because vault files are UTF-8 and the scanner works on bytes.
/// Line numbers everywhere in the scanner output are 1-based. A range never includes the line
/// terminator (`\n` or `\r\n`).
public struct ByteRange: Sendable, Hashable, Codable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start; self.end = max(start, end)
    }

    public var length: Int { end - start }
}

/// An ATX heading (`## Title`). Setext headings are not recognised (vault spec: ATX only).
public struct MarkdownHeading: Sendable, Hashable {
    /// 1...6.
    public var level: Int
    /// Text without the leading `#`s and the optional closing `#`s, trimmed.
    public var text: String
    public var line: Int
    public var range: ByteRange

    /// First and last line of the heading (always the same line for ATX).
    public var lines: ClosedRange<Int> { line...line }
}

/// A fenced (``` / ~~~) or indented code block.
public struct MarkdownCodeBlock: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case fenced, indented }

    public var kind: Kind
    /// Info string of a fenced block (`swift` in ```` ```swift ````), `nil` when absent.
    public var info: String?
    /// Lines from the opening fence to the closing fence (inclusive). For an unterminated fence
    /// the block runs to the last line of the document.
    public var lines: ClosedRange<Int>
    public var range: ByteRange
    /// `false` for a fence that was never closed (it runs to end of file).
    public var isTerminated: Bool
}

/// A task list item found outside code (`- [ ] text`, `* [x] text`, `+ [ ] text`).
public struct MarkdownTask: Sendable, Hashable {
    public var line: Int
    /// Indentation width in columns (a tab counts to the next multiple of 4).
    public var indent: Int
    /// The list marker character: `-`, `*` or `+`.
    public var marker: Character
    public var done: Bool
    /// Everything after `[ ] `, trimmed. Includes due tokens and the `^t-…` id.
    public var rawText: String
    /// Identifies the contiguous list the task belongs to; tasks with the same `listID` and
    /// increasing indentation are nested.
    public var listID: Int
    public var range: ByteRange
}

/// A link outside code: `[[wikilink]]`, `![[embed]]`, `[text](dest)` or `![alt](src)`.
public struct MarkdownLink: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case wikilink, markdown }

    public var kind: Kind
    public var isEmbed: Bool
    /// Wikilink: the raw text between `[[` and `]]`. Markdown link: the destination.
    public var inner: String
    /// Markdown link text (`nil` for wikilinks).
    public var label: String?
    public var line: Int
    /// Whole link including the leading `!` of an embed.
    public var range: ByteRange
}

/// Result of scanning one markdown document.
public struct MarkdownScan: Sendable, Hashable {
    public var headings: [MarkdownHeading] = []
    public var codeBlocks: [MarkdownCodeBlock] = []
    public var tasks: [MarkdownTask] = []
    public var links: [MarkdownLink] = []
    /// Lines occupied by the YAML frontmatter including both delimiters, `nil` when there is none.
    public var frontmatterLines: ClosedRange<Int>?
    /// Number of lines in the document.
    public var lineCount: Int = 0
}

/// Single-pass, line-oriented markdown scanner. Recognises only what Margin needs (headings,
/// code, tasks, links) and never throws: any input yields a result.
///
/// Rules:
/// - Frontmatter (`---` on line 1 up to the next `---` or `...`) is skipped completely. An
///   opening `---` without a closing line is not frontmatter.
/// - Everything inside fenced or indented code is ignored: no headings, tasks or links come
///   out of it. Inline code spans (`` `...` ``, matching backtick run lengths, single line) hide
///   links inside them.
/// - A fence needs 3+ backticks or tildes with at most 3 spaces of indentation (any indentation
///   inside a list). It is closed by a fence of the same character, at least as long, followed
///   only by whitespace. An unterminated fence runs to EOF.
/// - Indented code (4+ spaces or a tab) needs a preceding blank line and must not be inside a
///   list, so nested tasks (`    - [ ] x` under a list item) stay tasks. A fence at column 0
///   ends the list, like a paragraph or heading does.
public struct MarkdownScanner: Sendable {
    public init() {}

    public func scan(_ text: String) -> MarkdownScan {
        var impl = ScanState(bytes: Array(text.utf8))
        return impl.run()
    }
}

// MARK: - Implementation

private struct LineSpan {
    var start: Int      // first byte of the line
    var end: Int        // one past the last content byte (excludes \n / \r\n)
}

private struct ScanState {
    let bytes: [UInt8]
    var lines: [LineSpan] = []
    var result = MarkdownScan()

    init(bytes: [UInt8]) {
        self.bytes = bytes
        var start = 0
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x0A {
                let end = (i > start && bytes[i - 1] == 0x0D) ? i - 1 : i
                lines.append(LineSpan(start: start, end: end))
                start = i + 1
            }
            i += 1
        }
        if start < bytes.count { lines.append(LineSpan(start: start, end: bytes.count)) }
    }

    // Character constants
    static let space: UInt8 = 0x20, tab: UInt8 = 0x09
    static let backtick: UInt8 = 0x60, tilde: UInt8 = 0x7E
    static let hash: UInt8 = 0x23, dash: UInt8 = 0x2D, star: UInt8 = 0x2A, plus: UInt8 = 0x2B

    func isWS(_ b: UInt8) -> Bool { b == Self.space || b == Self.tab }

    func string(_ from: Int, _ to: Int) -> String {
        guard from < to else { return "" }
        return String(decoding: bytes[from..<to], as: UTF8.self)
    }

    func trimmed(_ from: Int, _ to: Int) -> (Int, Int) {
        var a = from, b = to
        while a < b, isWS(bytes[a]) { a += 1 }
        while b > a, isWS(bytes[b - 1]) { b -= 1 }
        return (a, b)
    }

    /// Indent width in columns and index of the first non-whitespace byte.
    func indent(of line: LineSpan) -> (cols: Int, idx: Int) {
        var cols = 0, i = line.start
        while i < line.end, isWS(bytes[i]) {
            cols += bytes[i] == Self.tab ? 4 - (cols % 4) : 1
            i += 1
        }
        return (cols, i)
    }

    mutating func run() -> MarkdownScan {
        result.lineCount = lines.count
        var idx = 0

        // Frontmatter.
        if let first = lines.first {
            var s = first.start
            if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { s = 3 }
            let (a, b) = trimmed(s, first.end)
            if string(a, b) == "---" {
                var j = 1
                while j < lines.count {
                    let (x, y) = trimmed(lines[j].start, lines[j].end)
                    let t = string(x, y)
                    if t == "---" || t == "..." {
                        result.frontmatterLines = 1...(j + 1)
                        idx = j + 1
                        break
                    }
                    j += 1
                }
            }
        }

        var prevBlank = true
        var inList = false
        var listID = 0

        // Fenced code state.
        var fenceChar: UInt8 = 0, fenceLen = 0, fenceStart = 0, fenceInfo: String?
        var inFence = false
        // Indented code state.
        var icStart: Int?, icLastNonBlank = 0

        func lineNo(_ i: Int) -> Int { i + 1 }

        while idx < lines.count {
            let line = lines[idx]
            let (cols, first) = indent(of: line)
            let blank = first >= line.end

            if inFence {
                if !blank, bytes[first] == fenceChar {
                    var j = first
                    while j < line.end, bytes[j] == fenceChar { j += 1 }
                    let (ra, rb) = trimmed(j, line.end)
                    if j - first >= fenceLen, ra >= rb {
                        closeFence(startIdx: fenceStart, endIdx: idx, info: fenceInfo, terminated: true)
                        inFence = false; prevBlank = true
                    }
                }
                idx += 1
                continue
            }

            if let start = icStart {
                if blank { idx += 1; continue }
                if cols >= 4 { icLastNonBlank = idx; idx += 1; continue }
                closeIndented(startIdx: start, endIdx: icLastNonBlank)
                icStart = nil
                prevBlank = true
                // fall through and handle this line normally
            }

            if blank {
                prevBlank = true
                idx += 1
                continue
            }

            // Fence opener.
            if cols <= 3 || inList,
               bytes[first] == Self.backtick || bytes[first] == Self.tilde {
                let ch = bytes[first]
                var j = first
                while j < line.end, bytes[j] == ch { j += 1 }
                let run = j - first
                if run >= 3 {
                    let (a, b) = trimmed(j, line.end)
                    let info = string(a, b)
                    let hasBacktick = info.utf8.contains(Self.backtick)
                    if !(ch == Self.backtick && hasBacktick) {
                        // A fence at column 0 is not list content, so it ends the list.
                        if cols == 0 { inList = false }
                        inFence = true
                        fenceChar = ch; fenceLen = run; fenceStart = idx
                        fenceInfo = info.isEmpty ? nil : info
                        idx += 1
                        continue
                    }
                }
            }

            // Indented code.
            if cols >= 4, !inList, prevBlank {
                icStart = idx; icLastNonBlank = idx
                idx += 1
                continue
            }

            // Heading.
            if cols <= 3, bytes[first] == Self.hash, let h = heading(line: line, first: first, lineIdx: idx) {
                result.headings.append(h)
                inList = false
                prevBlank = true
                scanLinks(line: line, lineIdx: idx)
                idx += 1
                continue
            }

            // List item / task.
            if let (markerEnd, marker) = bulletMarker(line: line, first: first) {
                if !inList { listID += 1 }
                inList = true
                if let (done, textStart) = taskBox(line: line, at: markerEnd) {
                    let (a, b) = trimmed(textStart, line.end)
                    if a < b {
                        result.tasks.append(MarkdownTask(
                            line: lineNo(idx), indent: cols, marker: marker, done: done,
                            rawText: string(a, b), listID: listID,
                            range: ByteRange(start: line.start, end: line.end)))
                    }
                }
            } else if orderedMarkerEnd(line: line, first: first) != nil {
                if !inList { listID += 1 }
                inList = true
            } else if cols == 0 {
                inList = false
            }

            prevBlank = false
            scanLinks(line: line, lineIdx: idx)
            idx += 1
        }

        if inFence {
            closeFence(startIdx: fenceStart, endIdx: lines.count - 1, info: fenceInfo, terminated: false)
        }
        if let start = icStart { closeIndented(startIdx: start, endIdx: icLastNonBlank) }
        return result
    }

    mutating func closeFence(startIdx: Int, endIdx: Int, info: String?, terminated: Bool) {
        result.codeBlocks.append(MarkdownCodeBlock(
            kind: .fenced, info: info, lines: (startIdx + 1)...(endIdx + 1),
            range: ByteRange(start: lines[startIdx].start, end: lines[endIdx].end),
            isTerminated: terminated))
    }

    mutating func closeIndented(startIdx: Int, endIdx: Int) {
        result.codeBlocks.append(MarkdownCodeBlock(
            kind: .indented, info: nil, lines: (startIdx + 1)...(endIdx + 1),
            range: ByteRange(start: lines[startIdx].start, end: lines[endIdx].end),
            isTerminated: true))
    }

    func heading(line: LineSpan, first: Int, lineIdx: Int) -> MarkdownHeading? {
        var j = first
        while j < line.end, bytes[j] == Self.hash { j += 1 }
        let level = j - first
        guard (1...6).contains(level), j == line.end || isWS(bytes[j]) else { return nil }
        var (a, b) = trimmed(j, line.end)
        // Optional closing sequence: trailing #s preceded by whitespace (or the whole content).
        var k = b
        while k > a, bytes[k - 1] == Self.hash { k -= 1 }
        if k < b, k == a || isWS(bytes[k - 1]) {
            b = k
            (a, b) = trimmed(a, b)
        }
        return MarkdownHeading(
            level: level, text: string(a, b), line: lineIdx + 1,
            range: ByteRange(start: line.start, end: line.end))
    }

    /// End of a `-`/`*`/`+` marker followed by whitespace or end of line.
    func bulletMarker(line: LineSpan, first: Int) -> (Int, Character)? {
        let b = bytes[first]
        guard b == Self.dash || b == Self.star || b == Self.plus else { return nil }
        let next = first + 1
        guard next == line.end || isWS(bytes[next]) else { return nil }
        return (next, Character(UnicodeScalar(b)))
    }

    func orderedMarkerEnd(line: LineSpan, first: Int) -> Int? {
        var j = first
        while j < line.end, bytes[j] >= 0x30, bytes[j] <= 0x39, j - first < 9 { j += 1 }
        guard j > first, j < line.end, bytes[j] == 0x2E || bytes[j] == 0x29 else { return nil }
        let next = j + 1
        guard next == line.end || isWS(bytes[next]) else { return nil }
        return next
    }

    /// `[ ]`, `[x]` or `[X]` after the marker, followed by whitespace or end of line.
    func taskBox(line: LineSpan, at markerEnd: Int) -> (done: Bool, textStart: Int)? {
        var j = markerEnd
        while j < line.end, isWS(bytes[j]) { j += 1 }
        guard j > markerEnd, j + 2 < line.end, bytes[j] == 0x5B, bytes[j + 2] == 0x5D else { return nil }
        let mark = bytes[j + 1]
        let done: Bool
        switch mark {
        case Self.space: done = false
        case 0x78, 0x58: done = true
        default: return nil
        }
        let after = j + 3
        guard after == line.end || isWS(bytes[after]) else { return nil }
        return (done, after)
    }

    // MARK: Links

    mutating func scanLinks(line: LineSpan, lineIdx: Int) {
        let s = line.start, e = line.end
        guard e - s >= 3 else { return }
        // Inline code mask.
        var masked = [Bool](repeating: false, count: e - s)
        var i = s
        while i < e {
            if bytes[i] == Self.backtick {
                var j = i
                while j < e, bytes[j] == Self.backtick { j += 1 }
                let run = j - i
                var k = j
                var closeEnd: Int?
                while k < e {
                    if bytes[k] == Self.backtick {
                        var m = k
                        while m < e, bytes[m] == Self.backtick { m += 1 }
                        if m - k == run { closeEnd = m; break }
                        k = m
                    } else { k += 1 }
                }
                if let c = closeEnd {
                    for p in i..<c { masked[p - s] = true }
                    i = c
                } else {
                    i = j
                }
            } else {
                i += 1
            }
        }

        func escaped(_ p: Int) -> Bool {
            var n = 0, q = p - 1
            while q >= s, bytes[q] == 0x5C { n += 1; q -= 1 }
            return n % 2 == 1
        }

        i = s
        while i < e {
            guard bytes[i] == 0x5B, !masked[i - s], !escaped(i) else { i += 1; continue }
            let embed = i > s && bytes[i - 1] == 0x21 && !masked[i - 1 - s] && !escaped(i - 1)
            let linkStart = embed ? i - 1 : i

            if i + 1 < e, bytes[i + 1] == 0x5B {
                // Wikilink.
                var j = i + 2
                var end: Int?
                while j < e {
                    if masked[j - s] { break }
                    let b = bytes[j]
                    if b == 0x5D {
                        if j + 1 < e, bytes[j + 1] == 0x5D { end = j; break }
                        break
                    }
                    if b == 0x5B { break }
                    j += 1
                }
                if let end {
                    let (a, b) = trimmed(i + 2, end)
                    if a < b {
                        result.links.append(MarkdownLink(
                            kind: .wikilink, isEmbed: embed, inner: string(i + 2, end), label: nil,
                            line: lineIdx + 1, range: ByteRange(start: linkStart, end: end + 2)))
                        i = end + 2
                        continue
                    }
                }
                i += 1
                continue
            }

            // Markdown link [text](dest).
            var depth = 1, j = i + 1
            var close: Int?
            while j < e {
                if masked[j - s] { j += 1; continue }
                let b = bytes[j]
                if b == 0x5C { j += 2; continue }
                if b == 0x5B { depth += 1 }
                if b == 0x5D { depth -= 1; if depth == 0 { close = j; break } }
                j += 1
            }
            if let close, close + 1 < e, bytes[close + 1] == 0x28 {
                var p = close + 2, pd = 1
                var paren: Int?
                while p < e {
                    let b = bytes[p]
                    if b == 0x5C { p += 2; continue }
                    if b == 0x28 { pd += 1 }
                    if b == 0x29 { pd -= 1; if pd == 0 { paren = p; break } }
                    p += 1
                }
                if let paren {
                    var (a, b) = trimmed(close + 2, paren)
                    if a < b, bytes[a] == 0x3C, let gt = bytes[a..<b].firstIndex(of: 0x3E) {
                        (a, b) = (a + 1, gt)
                    } else {
                        var w = a
                        while w < b, !isWS(bytes[w]) { w += 1 }
                        b = w
                    }
                    result.links.append(MarkdownLink(
                        kind: .markdown, isEmbed: embed, inner: string(a, b),
                        label: string(i + 1, close), line: lineIdx + 1,
                        range: ByteRange(start: linkStart, end: paren + 1)))
                    i = paren + 1
                    continue
                }
            }
            i += 1
        }
    }
}
