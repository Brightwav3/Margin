// Line-level markdown scanning for the editor tokenizer. Internal: the public surface is
// `MarkdownTokenizer` and `BlockModel`.
//
// A line is tokenized as a pure function of
//   (its text, the state at its start, the text of the next line, whether it is line 0 and whether
//    the document has frontmatter)
// which is what makes incremental retokenization exact: as soon as the state at the start of a line
// equals the state that line had before an edit, everything from there on is unchanged.

/// Block context carried from one line to the next.
struct LineState: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case normal
        case frontmatter
        case fence(char: UInt16, length: Int)
        case indented
    }

    var mode: Mode = .normal
    /// The previous line was blank (or the block ended, e.g. after a heading or a closing fence).
    var prevBlank = true
    /// Inside a list: the last list item was not followed by an unindented non-list line.
    var inList = false
    /// The previous line was accepted as a table header (the next line is its delimiter row).
    var tablePrev = false
    /// Inside a table body.
    var inTable = false

    static let initial = LineState()
}

/// What a single line is, used to group lines into blocks.
enum LineKind: Equatable, Sendable {
    case blank
    case frontmatter
    case fenceOpen(info: String?)
    case fenceBody
    case fenceClose
    case indentedCode
    case heading(level: Int)
    /// `task`: `nil` for a plain item, otherwise the checkbox state.
    case listItem(ordered: Bool, task: Bool?)
    /// Indented non-list line directly inside a list.
    case listContinuation
    case quote(callout: String?)
    case table
    case horizontalRule
    case paragraph
}

/// Token relative to the start of its line, so unchanged lines can be reused after a shift.
struct RelToken: Sendable, Hashable {
    var kind: MarkdownTokenKind
    var start: Int
    var length: Int
}

struct LineRecord: Sendable {
    var kind: LineKind
    /// State at the start of the next line.
    var exit: LineState
    var tokens: [RelToken]
}

private enum Construct {
    case code(start: Int, end: Int)
    case wiki(start: Int, end: Int, innerFrom: Int, innerTo: Int, embed: Bool)
    case link(start: Int, end: Int, textFrom: Int, textTo: Int, destFrom: Int, destTo: Int, embed: Bool)

    var end: Int {
        switch self {
        case .code(_, let e): e
        case .wiki(_, let e, _, _, _): e
        case .link(_, let e, _, _, _, _, _): e
        }
    }
}

struct LineScanner {
    let t: [UInt16]
    /// First code unit of the line.
    let start: Int
    /// One past the last content code unit (the line terminator is excluded).
    let end: Int
    var out: [RelToken] = []
    /// The line is a task item; enables `@due` tokens.
    var isTask = false

    init(text: [UInt16], start: Int, end: Int) {
        self.t = text; self.start = start; self.end = end
    }

    // MARK: Character helpers

    static let space: UInt16 = 0x20, tab: UInt16 = 0x09, cr: UInt16 = 0x0D
    static let backtick: UInt16 = 0x60, tilde: UInt16 = 0x7E, hash: UInt16 = 0x23
    static let dash: UInt16 = 0x2D, star: UInt16 = 0x2A, plus: UInt16 = 0x2B, underscore: UInt16 = 0x5F
    static let lbracket: UInt16 = 0x5B, rbracket: UInt16 = 0x5D, lparen: UInt16 = 0x28, rparen: UInt16 = 0x29
    static let backslash: UInt16 = 0x5C, bang: UInt16 = 0x21, pipe: UInt16 = 0x7C, gt: UInt16 = 0x3E

    @inline(__always) static func isWS(_ u: UInt16) -> Bool { u == space || u == tab }

    /// Whitespace for the purpose of "preceded by a space" checks inside a line.
    @inline(__always) static func isSpaceLike(_ u: UInt16) -> Bool { u == space || u == tab || u == cr }

    static func isAlnum(_ u: UInt16) -> Bool {
        (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u >= 0x80
    }

    static func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }

    static func isTagChar(_ u: UInt16) -> Bool {
        if u < 0x80 { return isAlnum(u) || u == underscore || u == dash || u == 0x2F }
        if u >= 0xD800 && u <= 0xDFFF { return true }
        guard let s = Unicode.Scalar(UInt32(u)) else { return false }
        return s.properties.isAlphabetic || s.properties.numericType != nil
    }

    func trim(_ a: Int, _ b: Int) -> (Int, Int) {
        var x = a, y = b
        while x < y, Self.isWS(t[x]) { x += 1 }
        while y > x, Self.isWS(t[y - 1]) { y -= 1 }
        return (x, y)
    }

    func indent(_ from: Int) -> (cols: Int, idx: Int) {
        var cols = 0, i = from
        while i < end, Self.isWS(t[i]) {
            cols += t[i] == Self.tab ? 4 - (cols % 4) : 1
            i += 1
        }
        return (cols, i)
    }

    func string(_ a: Int, _ b: Int) -> String {
        guard a < b else { return "" }
        return String(decoding: t[a..<b], as: UTF16.self)
    }

    mutating func add(_ kind: MarkdownTokenKind, _ a: Int, _ b: Int) {
        guard b > a else { return }
        out.append(RelToken(kind: kind, start: a - start, length: b - a))
    }

    func runLength(_ i: Int, _ to: Int, _ c: UInt16) -> Int {
        var k = 0
        while i + k < to, t[i + k] == c { k += 1 }
        return k
    }

    func containsPipe(_ a: Int, _ b: Int) -> Bool {
        var i = a
        while i < b { if t[i] == Self.pipe { return true }; i += 1 }
        return false
    }

    // MARK: Table helpers

    /// `| --- | :-: |` style delimiter row (needs at least one pipe).
    static func isDelimiterRow(_ t: [UInt16], _ from: Int, _ to: Int) -> Bool {
        var a = from, b = to
        while a < b, isWS(t[a]) { a += 1 }
        while b > a, isWS(t[b - 1]) { b -= 1 }
        guard a < b else { return false }
        var hasPipe = false
        var i = a
        while i < b { if t[i] == pipe { hasPipe = true; break }; i += 1 }
        guard hasPipe else { return false }
        if t[a] == pipe { a += 1 }
        if b > a, t[b - 1] == pipe { b -= 1 }
        guard a < b else { return false }
        var cells = 0
        var cs = a
        while cs <= b {
            var ce = cs
            while ce < b, t[ce] != pipe { ce += 1 }
            var x = cs, y = ce
            while x < y, isWS(t[x]) { x += 1 }
            while y > x, isWS(t[y - 1]) { y -= 1 }
            if x < y, t[x] == 0x3A { x += 1 }
            if x < y, t[y - 1] == 0x3A { y -= 1 }
            guard x < y else { return false }
            var k = x
            while k < y { if t[k] != dash { return false }; k += 1 }
            cells += 1
            cs = ce + 1
        }
        return cells >= 1
    }

    // MARK: Block level

    /// Tokenizes the line. Returns its kind and the state for the next line.
    mutating func run(index: Int, next: (start: Int, end: Int)?, entry: LineState,
                      hasFrontmatter: Bool) -> (LineKind, LineState) {
        var st = entry
        var ls = start
        if index == 0, ls < end, t[ls] == 0xFEFF { ls += 1 }

        if index == 0, hasFrontmatter {
            let (a, b) = trim(ls, end)
            add(.frontmatterDelimiter, a, b)
            return (.frontmatter, LineState(mode: .frontmatter, prevBlank: false, inList: false,
                                            tablePrev: false, inTable: false))
        }

        switch st.mode {
        case .frontmatter:
            let (a, b) = trim(ls, end)
            let n = b - a
            if n == 3, (t[a] == Self.dash && t[a + 1] == Self.dash && t[a + 2] == Self.dash)
                || (t[a] == 0x2E && t[a + 1] == 0x2E && t[a + 2] == 0x2E) {
                add(.frontmatterDelimiter, a, b)
                st = LineState(mode: .normal, prevBlank: true, inList: false, tablePrev: false, inTable: false)
            } else {
                add(.frontmatter, start, end)
            }
            return (.frontmatter, st)

        case .fence(let ch, let len):
            let (_, f) = indent(ls)
            if f < end, t[f] == ch {
                let run = runLength(f, end, ch)
                let (ra, rb) = trim(f + run, end)
                if run >= len, ra >= rb {
                    add(.codeFenceMarker, f, f + run)
                    st.mode = .normal
                    st.prevBlank = true
                    return (.fenceClose, st)
                }
            }
            add(.codeLine, start, end)
            return (.fenceBody, st)

        case .indented:
            let (cols, f) = indent(ls)
            if f >= end { return (.blank, st) }
            if cols >= 4 {
                add(.indentedCodeLine, start, end)
                return (.indentedCode, st)
            }
            st.mode = .normal
            st.prevBlank = true
            st.tablePrev = false
            st.inTable = false

        case .normal:
            break
        }

        // Normal mode.
        let (cols, f) = indent(ls)
        if f >= end {
            st.prevBlank = true; st.tablePrev = false; st.inTable = false
            return (.blank, st)
        }
        let first = t[f]
        let resetList: Bool = cols == 0

        // Indented code.
        if cols >= 4, st.prevBlank, !st.inList {
            add(.indentedCodeLine, start, end)
            return (.indentedCode, LineState(mode: .indented, prevBlank: false, inList: false,
                                             tablePrev: false, inTable: false))
        }

        // Fence opener.
        if cols <= 3 || st.inList, first == Self.backtick || first == Self.tilde {
            let run = runLength(f, end, first)
            if run >= 3 {
                let (ia, ib) = trim(f + run, end)
                var infoHasBacktick = false
                var k = ia
                while k < ib { if t[k] == Self.backtick { infoHasBacktick = true; break }; k += 1 }
                if !(first == Self.backtick && infoHasBacktick) {
                    add(.codeFenceMarker, f, f + run)
                    add(.codeInfo, ia, ib)
                    let info: String? = ia < ib ? string(ia, ib) : nil
                    return (.fenceOpen(info: info),
                            LineState(mode: .fence(char: first, length: run), prevBlank: false,
                                      inList: st.inList, tablePrev: false, inTable: false))
                }
            }
        }

        // Heading.
        if cols <= 3, first == Self.hash, let level = heading(f) {
            return (.heading(level: level),
                    LineState(mode: .normal, prevBlank: true, inList: false, tablePrev: false, inTable: false))
        }

        // Horizontal rule.
        if cols <= 3, first == Self.dash || first == Self.star || first == Self.underscore {
            var count = 0, k = f
            var ok = true
            while k < end {
                if t[k] == first { count += 1 } else if !Self.isWS(t[k]) { ok = false; break }
                k += 1
            }
            if ok, count >= 3 {
                let (a, b) = trim(f, end)
                add(.horizontalRule, a, b)
                return (.horizontalRule,
                        LineState(mode: .normal, prevBlank: true, inList: resetList ? false : st.inList,
                                  tablePrev: false, inTable: false))
            }
        }

        // Blockquote / callout.
        if cols <= 3, first == Self.gt {
            let callout = quote(f)
            return (.quote(callout: callout),
                    LineState(mode: .normal, prevBlank: false, inList: resetList ? false : st.inList,
                              tablePrev: false, inTable: false))
        }

        // Table delimiter row (line after an accepted header).
        if st.tablePrev {
            if Self.isDelimiterRow(t, ls, end) {
                let (a, b) = trim(ls, end)
                add(.tableDelimiterRow, a, b)
                return (.table, LineState(mode: .normal, prevBlank: false, inList: false,
                                          tablePrev: false, inTable: true))
            }
            st.tablePrev = false
        }

        // Table body row.
        if st.inTable {
            if containsPipe(ls, end) {
                let (a, b) = trim(ls, end)
                add(.tableRow(header: false), a, b)
                inline(a, b)
                return (.table, LineState(mode: .normal, prevBlank: false, inList: false,
                                          tablePrev: false, inTable: true))
            }
            st.inTable = false
        }

        // List item / task.
        if let (ordered, mEnd) = listMarker(f) {
            add(ordered ? .listOrdered : .listBullet, f, mEnd)
            var inlineStart = mEnd
            var task: Bool?
            if let box = taskBox(mEnd) {
                add(.taskCheckbox(checked: box.checked), box.start, box.start + 3)
                task = box.checked
                isTask = true
                inlineStart = box.after
            }
            inline(inlineStart, end)
            return (.listItem(ordered: ordered, task: task),
                    LineState(mode: .normal, prevBlank: false, inList: true, tablePrev: false, inTable: false))
        }

        // Table header (the next line must be a delimiter row).
        if containsPipe(ls, end), let n = next, Self.isDelimiterRow(t, n.start, n.end) {
            let (a, b) = trim(ls, end)
            add(.tableRow(header: true), a, b)
            inline(a, b)
            return (.table, LineState(mode: .normal, prevBlank: false, inList: false,
                                      tablePrev: true, inTable: false))
        }

        // Paragraph.
        let (a, _) = trim(ls, end)
        inline(a, end)
        let kind: LineKind = (st.inList && cols > 0) ? .listContinuation : .paragraph
        return (kind, LineState(mode: .normal, prevBlank: false, inList: resetList ? false : st.inList,
                                tablePrev: false, inTable: false))
    }

    /// ATX heading at `f` (a `#`). Returns the level and emits tokens, or `nil` when not a heading.
    mutating func heading(_ f: Int) -> Int? {
        var j = f
        while j < end, t[j] == Self.hash { j += 1 }
        let level = j - f
        guard (1...6).contains(level), j == end || Self.isWS(t[j]) else { return nil }
        var (a, b) = trim(j, end)
        var k = b
        while k > a, t[k - 1] == Self.hash { k -= 1 }
        if k < b, k == a || Self.isWS(t[k - 1]) {
            b = k
            (a, b) = trim(a, b)
        }
        add(.headingMarker(level: level), f, j)
        add(.headingText(level: level), a, b)
        inline(a, b)
        return level
    }

    /// Bullet or ordered marker at `f`. Returns whether it is ordered and the end of the marker.
    func listMarker(_ f: Int) -> (Bool, Int)? {
        let c = t[f]
        if c == Self.dash || c == Self.star || c == Self.plus {
            let n = f + 1
            guard n == end || Self.isWS(t[n]) else { return nil }
            return (false, n)
        }
        var j = f
        while j < end, Self.isDigit(t[j]), j - f < 9 { j += 1 }
        guard j > f, j < end, t[j] == 0x2E || t[j] == Self.rparen else { return nil }
        let n = j + 1
        guard n == end || Self.isWS(t[n]) else { return nil }
        return (true, n)
    }

    func taskBox(_ markerEnd: Int) -> (checked: Bool, start: Int, after: Int)? {
        var j = markerEnd
        while j < end, Self.isWS(t[j]) { j += 1 }
        guard j > markerEnd, j + 2 < end, t[j] == Self.lbracket, t[j + 2] == Self.rbracket else { return nil }
        let checked: Bool
        switch t[j + 1] {
        case Self.space: checked = false
        case 0x78, 0x58: checked = true
        default: return nil
        }
        let after = j + 3
        guard after == end || Self.isWS(t[after]) else { return nil }
        return (checked, j, after)
    }

    /// Blockquote line starting at `f` (a `>`). Returns the callout type when the quote opens one.
    mutating func quote(_ f: Int) -> String? {
        var p = f
        while true {
            add(.blockquoteMarker, p, p + 1)
            p += 1
            if p < end, Self.isWS(t[p]) { p += 1 }
            var q = p
            while q < end, Self.isWS(t[q]) { q += 1 }
            if q < end, t[q] == Self.gt { p = q } else { break }
        }
        var c = p
        while c < end, Self.isWS(t[c]) { c += 1 }
        guard c < end else { return nil }

        // Callout `[!type]`.
        if t[c] == Self.lbracket, c + 2 < end, t[c + 1] == Self.bang {
            var j = c + 2
            while j < end, Self.isAlnum(t[j]) || t[j] == Self.dash || t[j] == Self.underscore { j += 1 }
            if j > c + 2, j < end, t[j] == Self.rbracket {
                let type = string(c + 2, j).lowercased()
                add(.callout(type: type), c, j + 1)
                inline(j + 1, end)
                return type
            }
        }
        if t[c] == Self.hash, heading(c) != nil { return nil }
        if let (ordered, mEnd) = listMarker(c) {
            add(ordered ? .listOrdered : .listBullet, c, mEnd)
            var inlineStart = mEnd
            if let box = taskBox(mEnd) {
                add(.taskCheckbox(checked: box.checked), box.start, box.start + 3)
                isTask = true
                inlineStart = box.after
            }
            inline(inlineStart, end)
            return nil
        }
        inline(c, end)
        return nil
    }

    // MARK: Inline

    /// Scans `from ..< to` for inline constructs. All constructs are single-line.
    mutating func inline(_ from: Int, _ to: Int) {
        var i = from
        while i < to {
            let c = t[i]
            switch c {
            case Self.backslash:
                i += 2
            case Self.backtick, Self.bang, Self.lbracket:
                if let cons = construct(at: i, to: to) {
                    emit(cons)
                    i = cons.end
                } else if c == Self.backtick {
                    i += runLength(i, to, c)
                } else {
                    i += 1
                }
            case Self.star, Self.underscore, Self.tilde:
                i = emphasis(at: i, from: from, to: to)
            case Self.hash:
                i = tag(at: i, from: from, to: to)
            case 0x40:
                i = due(at: i, from: from, to: to)
            case 0x5E:
                i = blockID(at: i, from: from, to: to)
            default:
                i += 1
            }
        }
    }

    private mutating func emit(_ cons: Construct) {
        switch cons {
        case .code(let s, let e):
            add(.inlineCode, s, e)
        case .wiki(let s, let e, let a, let b, let embed):
            add(.wikilink(embed: embed), s, e)
            var p: Int?
            var h: Int?
            var k = a
            while k < b {
                if t[k] == Self.pipe { p = k; break }
                if t[k] == Self.hash, h == nil { h = k }
                k += 1
            }
            var pe = p
            if let pp = p, pp > a, t[pp - 1] == Self.backslash { pe = pp - 1 }
            let targetEnd = h ?? pe ?? b
            add(.wikilinkTarget, a, targetEnd)
            if let hh = h { add(.wikilinkHeading, hh + 1, pe ?? b) }
            if let pp = p { add(.wikilinkAlias, pp + 1, b) }
        case .link(let s, let e, let tf, let tt, let df, let dt, let embed):
            add(.link(embed: embed), s, e)
            add(.linkText, tf, tt)
            inline(tf, tt)
            add(.linkDestination, df, dt)
        }
    }

    /// Code span, wikilink, embed or markdown link starting at `i`.
    private func construct(at i: Int, to: Int) -> Construct? {
        let c = t[i]
        if c == Self.backtick {
            let run = runLength(i, to, c)
            var k = i + run
            while k < to {
                if t[k] == Self.backtick {
                    let m = runLength(k, to, c)
                    if m == run {
                        return .code(start: i, end: k + m)
                    }
                    k += m
                } else { k += 1 }
            }
            return nil
        }
        var embed = false
        var b = i
        if c == Self.bang {
            guard i + 1 < to, t[i + 1] == Self.lbracket else { return nil }
            embed = true
            b = i + 1
        }
        guard t[b] == Self.lbracket else { return nil }
        if b + 1 < to, t[b + 1] == Self.lbracket {
            // Wikilink.
            var q = b + 2
            while q + 1 < to {
                if t[q] == Self.rbracket, t[q + 1] == Self.rbracket {
                    guard q > b + 2 else { return nil }
                    return .wiki(start: i, end: q + 2, innerFrom: b + 2, innerTo: q, embed: embed)
                }
                q += 1
            }
            return nil
        }
        // Markdown link.
        var depth = 1
        var j = b + 1
        var rb = -1
        while j < to {
            let u = t[j]
            if u == Self.backslash { j += 2; continue }
            if u == Self.backtick {
                let run = runLength(j, to, u)
                var k = j + run
                var closed = -1
                while k < to {
                    if t[k] == Self.backtick {
                        let m = runLength(k, to, u)
                        if m == run { closed = k + m; break }
                        k += m
                    } else { k += 1 }
                }
                j = closed >= 0 ? closed : j + run
                continue
            }
            if u == Self.lbracket { depth += 1 } else if u == Self.rbracket {
                depth -= 1
                if depth == 0 { rb = j; break }
            }
            j += 1
        }
        guard rb >= 0, rb + 1 < to, t[rb + 1] == Self.lparen else { return nil }
        var pd = 1
        var k = rb + 2
        var rp = -1
        while k < to {
            let u = t[k]
            if u == Self.backslash { k += 2; continue }
            if u == Self.lparen { pd += 1 } else if u == Self.rparen {
                pd -= 1
                if pd == 0 { rp = k; break }
            }
            k += 1
        }
        guard rp >= 0 else { return nil }
        var da = rb + 2
        while da < rp, Self.isWS(t[da]) { da += 1 }
        var db: Int
        if da < rp, t[da] == 0x3C, let gt = (da + 1..<rp).first(where: { t[$0] == Self.gt }) {
            da += 1
            db = gt
        } else {
            db = da
            while db < rp, !Self.isWS(t[db]) { db += 1 }
        }
        return .link(start: i, end: rp + 1, textFrom: b + 1, textTo: rb, destFrom: da, destTo: db, embed: embed)
    }
}

// MARK: - Emphasis, tags, due tokens, block ids

extension LineScanner {
    /// Emphasis / strong / strikethrough opener at `i`. Returns the index to continue from.
    mutating func emphasis(at i: Int, from: Int, to: Int) -> Int {
        let c = t[i]
        let n = runLength(i, to, c)
        let isTilde = c == Self.tilde
        if isTilde, n != 2 { return i + n }
        guard i + n < to, !Self.isSpaceLike(t[i + n]) else { return i + n }
        if c == Self.underscore, i > from, Self.isAlnum(t[i - 1]) { return i + n }

        // Find the closing run.
        var j = i + n
        var closeAt = -1, closeLen = 0
        while j < to {
            let u = t[j]
            if u == Self.backslash { j += 2; continue }
            if u == Self.backtick || u == Self.bang || u == Self.lbracket {
                if let cons = construct(at: j, to: to) { j = cons.end; continue }
                j += u == Self.backtick ? runLength(j, to, u) : 1
                continue
            }
            if u == c {
                let m = runLength(j, to, c)
                let lengthOK = n >= 3 ? m >= 3 : m == n
                if j > i + n, lengthOK, !Self.isSpaceLike(t[j - 1]),
                   c != Self.underscore || j + m >= to || !Self.isAlnum(t[j + m]) {
                    closeAt = j; closeLen = m
                    break
                }
                j += m
                continue
            }
            j += 1
        }
        guard closeAt >= 0 else { return i + n }

        if !isTilde, n >= 3, closeLen >= 3 {
            let os = i + n - 3
            add(.emphasis, os, closeAt + 3)
            add(.strong, os + 1, closeAt + 2)
            inline(os + 3, closeAt)
            return closeAt + 3
        }
        let use = isTilde ? 2 : min(n, closeLen, 2)
        let os = i + n - use
        let ce = closeAt + use
        add(isTilde ? .strikethrough : (use == 2 ? .strong : .emphasis), os, ce)
        inline(os + use, closeAt)
        return ce
    }

    mutating func tag(at i: Int, from: Int, to: Int) -> Int {
        guard i == from || Self.isSpaceLike(t[i - 1]) else { return i + 1 }
        var j = i + 1
        var hasNonDigit = false
        while j < to, Self.isTagChar(t[j]) {
            if !Self.isDigit(t[j]) { hasNonDigit = true }
            j += 1
        }
        guard j > i + 1, hasNonDigit else { return i + 1 }
        add(.tag, i, j)
        return j
    }

    mutating func due(at i: Int, from: Int, to: Int) -> Int {
        guard isTask, i == from || Self.isSpaceLike(t[i - 1]) else { return i + 1 }
        var w = i + 1
        while w < to, Self.isWS(t[w]) { w += 1 }
        var e = w
        while e < to, Self.isDueChar(t[e]) { e += 1 }
        guard e > w, DueToken(word: string(w, e)) != nil else { return i + 1 }
        add(.due, i, e)
        return e
    }

    mutating func blockID(at i: Int, from: Int, to: Int) -> Int {
        guard i == from || Self.isSpaceLike(t[i - 1]) else { return i + 1 }
        var j = i + 1
        while j < to, Self.isDueChar(t[j]) { j += 1 }
        guard j > i + 1 else { return i + 1 }
        var k = j
        while k < end, Self.isWS(t[k]) { k += 1 }
        guard k == end else { return i + 1 }
        add(.blockID, i, j)
        return j
    }

    /// ASCII letters, digits and `-`.
    static func isDueChar(_ u: UInt16) -> Bool {
        (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u == dash
    }
}
