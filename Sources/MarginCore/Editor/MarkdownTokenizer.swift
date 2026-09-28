/// Result of `MarkdownTokenizer.update`: what had to be retokenized.
public struct TokenizerUpdate: Sendable, Hashable {
    /// Lines (in the new document) whose tokens were recomputed. Tokens outside these lines are
    /// unchanged, apart from being shifted by the edit.
    public var retokenizedLines: Range<Int>
    /// Text range of `retokenizedLines` in the new document (line contents, without the final
    /// line terminator). A highlighter only needs to restyle this range.
    public var changedRange: TextRange
    /// `true` when the whole document was retokenized (frontmatter appeared or disappeared).
    public var wasFullRetokenize: Bool
}

/// Incremental markdown tokenizer for the editor.
///
/// All offsets are **UTF-16 code units**, because the Mac editor is an `NSTextView` whose
/// `NSRange` counts UTF-16 units (see `TextRange`). The tokenizer keeps its own copy of the text
/// (`string`), so the editor forwards every text change with `update(edit:replacement:)`.
///
/// Lines are separated by `\\n` (a `\\r` directly before it belongs to the terminator). The document
/// always has at least one line; a text ending in `\\n` ends with an empty line.
///
/// ## Incrementality
/// Each line is tokenized as a pure function of its text, the block state at its start (open
/// fence, frontmatter, list, table, ...) and the following line (a table header is only a header
/// if a delimiter row follows). `update` retokenizes the edited lines plus the line before them,
/// then keeps going only while the block state at the start of a line differs from the one it had
/// before the edit. Changing a fence marker therefore re-scans up to the matching fence (or the
/// end of the document) and nothing else. The result is always identical to tokenizing the new
/// text from scratch (`MarkdownTokenizer(text:)`), which the tests verify with seeded random edits.
///
/// Frontmatter is the one document-wide rule (`---` on line 0 only opens frontmatter if a closing
/// line exists). If an edit changes that, the document is retokenized in full.
///
/// Inline constructs are single-line. Not supported: setext headings, HTML blocks, reference
/// links, fences inside blockquotes, emphasis across lines.
public struct MarkdownTokenizer: Sendable {
    private var text: [UInt16]
    /// Start offset of each line; `lineStarts.count == records.count`.
    private var lineStarts: [Int]
    private var records: [LineRecord]
    private var hasFrontmatter: Bool

    public init(text: String = "") {
        self.text = Array(text.utf16)
        self.lineStarts = [0]
        self.records = []
        self.hasFrontmatter = false
        rebuildAll()
    }

    // MARK: Reading

    /// The current document text.
    public var string: String { String(decoding: text, as: UTF16.self) }

    /// Length of the document in UTF-16 code units.
    public var utf16Count: Int { text.count }

    public var lineCount: Int { records.count }

    /// Text range of line `index` (content only, no terminator). `nil` when out of bounds.
    public func lineRange(_ index: Int) -> TextRange? {
        guard index >= 0, index < records.count else { return nil }
        return TextRange(location: lineStarts[index], length: contentEnd(of: index) - lineStarts[index])
    }

    /// Index of the line containing `offset` (clamped to the document). An offset on a line
    /// terminator belongs to the line the terminator ends.
    public func lineIndex(containing offset: Int) -> Int {
        lastLineIndex(in: lineStarts, offset: offset)
    }

    /// All tokens of the document in order.
    public var tokens: [MarkdownToken] {
        var result: [MarkdownToken] = []
        result.reserveCapacity(records.count * 2)
        for i in 0..<records.count { append(line: i, to: &result) }
        return result
    }

    /// Tokens of the lines intersecting `range`, for restyling a visible or changed range. Tokens
    /// that do not intersect `range` but sit on those lines are included.
    public func tokens(in range: TextRange) -> [MarkdownToken] {
        guard !records.isEmpty else { return [] }
        let first = lineIndex(containing: range.location)
        let last = lineIndex(containing: range.end)
        var result: [MarkdownToken] = []
        for i in first...last { append(line: i, to: &result) }
        return result
    }

    /// Tokenizes `text` from scratch.
    public static func tokenize(_ text: String) -> [MarkdownToken] {
        MarkdownTokenizer(text: text).tokens
    }

    /// The document split into blocks, for live preview.
    public func blockModel() -> BlockModel {
        BlockModel(lineStarts: lineStarts, lineEnds: (0..<records.count).map { contentEnd(of: $0) },
                   kinds: records.map(\.kind))
    }

    // MARK: Editing

    /// Replaces `range` with `replacement` and retokenizes only what the change can affect.
    ///
    /// `range` is clamped to the document. The result is identical to
    /// `MarkdownTokenizer(text: newText)`.
    @discardableResult
    public mutating func update(edit range: TextRange, replacement: String) -> TokenizerUpdate {
        let lower = min(range.location, text.count)
        let upper = min(max(range.end, lower), text.count)
        let repl = Array(replacement.utf16)
        let delta = repl.count - (upper - lower)

        let oldLineCount = records.count
        let oldFirst = lastLineIndex(in: lineStarts, offset: lower)
        let oldLast = lastLineIndex(in: lineStarts, offset: upper)
        let hadFrontmatter = hasFrontmatter

        text.replaceSubrange(lower..<upper, with: repl)

        // Rebuild the line starts of the edited region; shift the ones after it.
        let regionStart = lineStarts[oldFirst]
        let suffixExists = oldLast + 1 < oldLineCount
        let regionEnd = suffixExists ? lineStarts[oldLast + 1] + delta : text.count
        var mid: [Int] = []
        var p = regionStart
        while p < regionEnd {
            if text[p] == 0x0A {
                let q = p + 1
                if q < regionEnd || (!suffixExists && q <= regionEnd) { mid.append(q) }
            }
            p += 1
        }
        lineStarts.replaceSubrange((oldFirst + 1)..<(oldLast + 1), with: mid)
        let newLast = oldFirst + mid.count
        if delta != 0, newLast + 1 < lineStarts.count {
            for k in (newLast + 1)..<lineStarts.count { lineStarts[k] += delta }
        }
        let lineShift = mid.count - (oldLast - oldFirst)

        hasFrontmatter = computeHasFrontmatter()
        if hasFrontmatter != hadFrontmatter {
            // Placeholder records so `rebuildAll` can size the array.
            rebuildAll()
            return TokenizerUpdate(
                retokenizedLines: 0..<records.count,
                changedRange: TextRange(location: 0, length: text.count),
                wasFullRetokenize: true)
        }

        // The end of the edit in the new text can sit on a later line than `newLast` computed
        // from the old structure only through the replacement text, which `mid` already covers.
        let begin = max(0, oldFirst - 1)
        var state = begin == 0 ? LineState.initial : records[begin - 1].exit
        var fresh: [LineRecord] = []
        var i = begin
        var resumeOld = -1   // index of the first reused old line, if any
        let lineTotal = lineStarts.count
        while i < lineTotal {
            if i > newLast {
                let oi = i - lineShift
                if oi < oldLineCount, records[oi - 1].exit == state {
                    resumeOld = oi
                    break
                }
            }
            let rec = tokenize(line: i, entry: state)
            state = rec.exit
            fresh.append(rec)
            i += 1
        }
        let replacedEnd = resumeOld >= 0 ? resumeOld : oldLineCount
        records.replaceSubrange(begin..<replacedEnd, with: fresh)

        let lastLine = begin + fresh.count - 1
        let changedStart = lineStarts[begin]
        let changedEnd = contentEnd(of: max(begin, lastLine))
        return TokenizerUpdate(
            retokenizedLines: begin..<(begin + fresh.count),
            changedRange: TextRange(location: changedStart, length: max(0, changedEnd - changedStart)),
            wasFullRetokenize: false)
    }

    // MARK: Internals

    private mutating func rebuildAll() {
        var starts = [0]
        for (i, u) in text.enumerated() where u == 0x0A { starts.append(i + 1) }
        lineStarts = starts
        hasFrontmatter = computeHasFrontmatter()
        var recs: [LineRecord] = []
        recs.reserveCapacity(starts.count)
        var state = LineState.initial
        for i in 0..<starts.count {
            let rec = tokenize(line: i, entry: state)
            state = rec.exit
            recs.append(rec)
        }
        records = recs
    }

    private func contentEnd(of line: Int) -> Int {
        if line + 1 < lineStarts.count {
            let nl = lineStarts[line + 1] - 1
            return (nl > lineStarts[line] && text[nl - 1] == 0x0D) ? nl - 1 : nl
        }
        return text.count
    }

    private func tokenize(line i: Int, entry: LineState) -> LineRecord {
        let s = lineStarts[i]
        let e = contentEnd(of: i)
        var scanner = LineScanner(text: text, start: s, end: e)
        var next: (start: Int, end: Int)?
        if i + 1 < lineStarts.count { next = (lineStarts[i + 1], contentEnd(of: i + 1)) }
        let (kind, exit) = scanner.run(index: i, next: next, entry: entry, hasFrontmatter: hasFrontmatter)
        return LineRecord(kind: kind, exit: exit, tokens: scanner.out)
    }

    /// Line 0 is `---` and a later line is `---` or `...`.
    private func computeHasFrontmatter() -> Bool {
        guard lineStarts.count > 1 else { return false }
        func trimmedIs(_ line: Int, _ candidates: [[UInt16]], skipBOM: Bool) -> Bool {
            var a = lineStarts[line]
            var b = contentEnd(of: line)
            if skipBOM, a < b, text[a] == 0xFEFF { a += 1 }
            while a < b, LineScanner.isWS(text[a]) { a += 1 }
            while b > a, LineScanner.isWS(text[b - 1]) { b -= 1 }
            guard b - a == 3 else { return false }
            return candidates.contains { $0[0] == text[a] && $0[1] == text[a + 1] && $0[2] == text[a + 2] }
        }
        let dashes: [UInt16] = [0x2D, 0x2D, 0x2D], dots: [UInt16] = [0x2E, 0x2E, 0x2E]
        guard trimmedIs(0, [dashes], skipBOM: true) else { return false }
        for j in 1..<lineStarts.count where trimmedIs(j, [dashes, dots], skipBOM: false) { return true }
        return false
    }

    private func append(line i: Int, to result: inout [MarkdownToken]) {
        let s = lineStarts[i]
        for r in records[i].tokens {
            result.append(MarkdownToken(kind: r.kind, range: TextRange(location: s + r.start, length: r.length)))
        }
    }
}

/// Index of the last line starting at or before `offset` (clamped).
func lastLineIndex(in starts: [Int], offset: Int) -> Int {
    var lo = 0, hi = starts.count - 1
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
    }
    return lo
}
