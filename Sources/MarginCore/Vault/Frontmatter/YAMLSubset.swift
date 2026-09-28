/// A small YAML subset sufficient for the vault spec: plain / single / double quoted scalars,
/// flow lists and maps, block lists and block maps, `#` comments, `|` and `>` block scalars
/// (top level only). Everything works on UTF-8 bytes: all delimiters are ASCII, so slicing is
/// always valid, and grapheme rules (`\r\n` is one `Character`) never interfere.
///
/// Every function returns `nil` for malformed input instead of trapping. Nesting is depth-limited
/// so arbitrary garbage cannot overflow the stack.
enum YAMLSubset {
    static let maxDepth = 32

    // MARK: Byte helpers

    static let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t")
    static let dq = UInt8(ascii: "\""), sq = UInt8(ascii: "'"), backslash = UInt8(ascii: "\\")
    static let hash = UInt8(ascii: "#"), colon = UInt8(ascii: ":"), dash = UInt8(ascii: "-")
    static let comma = UInt8(ascii: ","), lbracket = UInt8(ascii: "["), rbracket = UInt8(ascii: "]")
    static let lbrace = UInt8(ascii: "{"), rbrace = UInt8(ascii: "}")

    static func isSpace(_ b: UInt8) -> Bool { b == space || b == tab }

    static func trim(_ s: ArraySlice<UInt8>) -> [UInt8] {
        var lo = s.startIndex, hi = s.endIndex
        while lo < hi, isSpace(s[lo]) { lo += 1 }
        while hi > lo, isSpace(s[hi - 1]) { hi -= 1 }
        return Array(s[lo..<hi])
    }

    static func trimTrailing(_ s: [UInt8]) -> [UInt8] {
        var hi = s.count
        while hi > 0, isSpace(s[hi - 1]) { hi -= 1 }
        return Array(s[0..<hi])
    }

    static func string(_ b: some Collection<UInt8>) -> String { String(decoding: b, as: UTF8.self) }

    // MARK: Comments

    /// Index of the `#` that starts a trailing comment (preceded by whitespace, outside quotes).
    static func commentStart(_ t: [UInt8]) -> Int? {
        var i = 0
        var prevSig: UInt8?
        var prevSpace = true
        while i < t.count {
            let b = t[i]
            if (b == dq || b == sq), opensQuote(prevSig) {
                guard let end = skipQuoted(t, at: i) else { return nil }
                i = end
                prevSig = b
                prevSpace = false
                continue
            }
            if b == hash, prevSpace { return i }
            if isSpace(b) {
                prevSpace = true
            } else {
                prevSpace = false
                prevSig = b
            }
            i += 1
        }
        return nil
    }

    private static func opensQuote(_ prev: UInt8?) -> Bool {
        guard let p = prev else { return true }
        return p == lbracket || p == lbrace || p == comma || p == colon || p == dash
    }

    /// Index just after the closing quote of the quoted scalar starting at `i`.
    private static func skipQuoted(_ t: [UInt8], at i: Int) -> Int? {
        let q = t[i]
        var j = i + 1
        while j < t.count {
            if q == dq, t[j] == backslash { j += 2; continue }
            if t[j] == q {
                if q == sq, j + 1 < t.count, t[j + 1] == sq { j += 2; continue }
                return j + 1
            }
            j += 1
        }
        return nil
    }

    // MARK: Keys

    /// Parses a `key:` prefix of a line that starts at its first significant byte.
    /// `restStart` is the index right after the colon.
    static func keyLine(_ t: [UInt8]) -> (key: String, restStart: Int)? {
        guard let f = t.first else { return nil }
        if f == dq || f == sq {
            guard let (key, end) = parseQuoted(t, at: 0) else { return nil }
            var i = end
            while i < t.count, isSpace(t[i]) { i += 1 }
            guard i < t.count, t[i] == colon, i + 1 == t.count || isSpace(t[i + 1]) else { return nil }
            return (key, i + 1)
        }
        if "#[{?!&*|>%@`,".utf8.contains(f) { return nil }
        if isDashItem(t) { return nil }
        var i = 0
        while i < t.count {
            if t[i] == colon, i + 1 == t.count || isSpace(t[i + 1]) {
                let key = trim(t[0..<i][...])
                if key.isEmpty { return nil }
                return (string(key), i + 1)
            }
            if isSpace(t[i]), i + 1 < t.count, t[i + 1] == hash { return nil }
            i += 1
        }
        return nil
    }

    /// `-` alone or followed by whitespace.
    static func isDashItem(_ t: [UInt8]) -> Bool {
        guard t.first == dash else { return false }
        return t.count == 1 || isSpace(t[1])
    }

    // MARK: Scalars

    static func parseQuoted(_ t: [UInt8], at i: Int) -> (String, Int)? {
        guard i < t.count else { return nil }
        let q = t[i]
        var out: [UInt8] = []
        var j = i + 1
        while j < t.count {
            let b = t[j]
            if q == sq {
                if b == sq {
                    if j + 1 < t.count, t[j + 1] == sq { out.append(sq); j += 2; continue }
                    return (string(out), j + 1)
                }
                out.append(b)
                j += 1
                continue
            }
            if b == dq { return (string(out), j + 1) }
            if b != backslash { out.append(b); j += 1; continue }
            j += 1
            guard j < t.count else { return nil }
            switch t[j] {
            case UInt8(ascii: "n"): out.append(0x0A)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "r"): out.append(0x0D)
            case UInt8(ascii: "0"): out.append(0x00)
            case UInt8(ascii: "a"): out.append(0x07)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "e"): out.append(0x1B)
            case UInt8(ascii: "f"): out.append(0x0C)
            case UInt8(ascii: "v"): out.append(0x0B)
            case UInt8(ascii: "/"): out.append(UInt8(ascii: "/"))
            case UInt8(ascii: " "): out.append(space)
            case dq: out.append(dq)
            case backslash: out.append(backslash)
            case UInt8(ascii: "x"), UInt8(ascii: "u"), UInt8(ascii: "U"):
                let n = t[j] == UInt8(ascii: "x") ? 2 : (t[j] == UInt8(ascii: "u") ? 4 : 8)
                guard j + n < t.count, let v = hex(t[(j + 1)...(j + n)]),
                      let scalar = Unicode.Scalar(v) else { return nil }
                out.append(contentsOf: Array(String(Character(scalar)).utf8))
                j += n
            default: return nil
            }
            j += 1
        }
        return nil
    }

    private static func hex(_ s: ArraySlice<UInt8>) -> UInt32? {
        var v: UInt32 = 0
        for b in s {
            guard let d = Character(Unicode.Scalar(b)).hexDigitValue else { return nil }
            v = v &* 16 &+ UInt32(d)
        }
        return v
    }

    /// Resolves a plain (unquoted, trimmed) scalar: null, bool, date, date-time, number or string.
    static func resolvePlain(_ t: [UInt8]) -> FrontmatterValue {
        let s = string(t)
        switch s {
        case "", "~", "null", "Null", "NULL": return .null
        case "true", "True", "TRUE": return .bool(true)
        case "false", "False", "FALSE": return .bool(false)
        default: break
        }
        if let f = t.first, (f >= 0x30 && f <= 0x39) || f == dash {
            if let d = LocalDate(iso: s) { return .date(d) }
            if let dt = LocalDateTime(iso: s) { return .dateTime(dt) }
        }
        if let f = t.first, (f >= 0x30 && f <= 0x39) || f == dash || f == UInt8(ascii: "+") || f == UInt8(ascii: "."),
           t.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || "+-.eE".utf8.contains($0) }),
           let d = Double(s), d.isFinite
        {
            return .number(d)
        }
        return .string(s)
    }

    /// Parses a single-line inline value (already comment-stripped and trimmed).
    static func parseInline(_ t: [UInt8], depth: Int = 0) -> FrontmatterValue? {
        guard let f = t.first else { return .null }
        switch f {
        case lbracket, lbrace:
            var i = 0
            guard let v = flowValue(t, &i, depth: depth) else { return nil }
            while i < t.count, isSpace(t[i]) { i += 1 }
            return i == t.count ? v : nil
        case dq, sq:
            guard let (s, end) = parseQuoted(t, at: 0) else { return nil }
            return t[end...].allSatisfy(isSpace) ? .string(s) : nil
        case UInt8(ascii: "|"), UInt8(ascii: ">"), UInt8(ascii: "&"), UInt8(ascii: "*"),
             UInt8(ascii: "!"), UInt8(ascii: "@"), UInt8(ascii: "`"):
            return nil
        default:
            for i in t.indices where t[i] == colon && (i + 1 == t.count || isSpace(t[i + 1])) { return nil }
            return resolvePlain(t)
        }
    }

    // MARK: Flow collections

    private static func skipSpaces(_ t: [UInt8], _ i: inout Int) {
        while i < t.count, isSpace(t[i]) { i += 1 }
    }

    static func flowValue(_ t: [UInt8], _ i: inout Int, depth: Int) -> FrontmatterValue? {
        guard depth < maxDepth else { return nil }
        skipSpaces(t, &i)
        guard i < t.count else { return nil }
        switch t[i] {
        case lbracket:
            i += 1
            var items: [FrontmatterValue] = []
            while true {
                skipSpaces(t, &i)
                guard i < t.count else { return nil }
                if t[i] == rbracket { i += 1; return .list(items) }
                guard let v = flowValue(t, &i, depth: depth + 1) else { return nil }
                items.append(v)
                skipSpaces(t, &i)
                guard i < t.count else { return nil }
                if t[i] == comma { i += 1 } else if t[i] != rbracket { return nil }
            }
        case lbrace:
            i += 1
            var pairs: [FrontmatterValue.Pair] = []
            while true {
                skipSpaces(t, &i)
                guard i < t.count else { return nil }
                if t[i] == rbrace { i += 1; return .map(pairs) }
                guard let key = flowKey(t, &i) else { return nil }
                skipSpaces(t, &i)
                var value = FrontmatterValue.null
                if i < t.count, t[i] == colon, i + 1 == t.count || flowDelimiter(t[i + 1]) {
                    i += 1
                    skipSpaces(t, &i)
                    if i < t.count, t[i] != comma, t[i] != rbrace {
                        guard let v = flowValue(t, &i, depth: depth + 1) else { return nil }
                        value = v
                    }
                }
                pairs.append(.init(key, value))
                skipSpaces(t, &i)
                guard i < t.count else { return nil }
                if t[i] == comma { i += 1 } else if t[i] != rbrace { return nil }
            }
        case dq, sq:
            guard let (s, end) = parseQuoted(t, at: i) else { return nil }
            i = end
            return .string(s)
        default:
            let start = i
            while i < t.count, t[i] != comma, t[i] != rbracket, t[i] != rbrace { i += 1 }
            let text = trim(t[start..<i])
            if text.isEmpty { return nil }
            if let f = text.first, "&*!@`|>".utf8.contains(f) { return nil }
            return resolvePlain(text)
        }
    }

    private static func flowDelimiter(_ b: UInt8) -> Bool {
        isSpace(b) || b == comma || b == rbrace || b == rbracket
    }

    private static func flowKey(_ t: [UInt8], _ i: inout Int) -> String? {
        if t[i] == dq || t[i] == sq {
            guard let (s, end) = parseQuoted(t, at: i) else { return nil }
            i = end
            return s
        }
        let start = i
        while i < t.count, t[i] != comma, t[i] != rbrace {
            if t[i] == colon, i + 1 == t.count || flowDelimiter(t[i + 1]) { break }
            i += 1
        }
        let key = trim(t[start..<i])
        return key.isEmpty ? nil : string(key)
    }

    // MARK: Block collections

    struct Line {
        var indent: Int
        var text: [UInt8]
    }

    /// Logical lines: blank and comment-only lines dropped, comments stripped, indentation counted.
    /// Returns `nil` when indentation uses tabs.
    static func logicalLines(_ contents: [[UInt8]]) -> [Line]? {
        var out: [Line] = []
        for c in contents {
            var indent = 0
            while indent < c.count, c[indent] == space { indent += 1 }
            var text = Array(c[indent...])
            if let f = text.first, f == tab { return nil }
            if text.isEmpty || text.allSatisfy(isSpace) { continue }
            if text.first == hash { continue }
            if let cs = commentStart(text) { text = Array(text[0..<cs]) }
            text = trim(text[...])
            if text.isEmpty { continue }
            out.append(Line(indent: indent, text: text))
        }
        return out
    }

    static func parseBlock(_ ls: inout [Line], _ pos: inout Int, depth: Int) -> FrontmatterValue? {
        guard depth < maxDepth, pos < ls.count else { return nil }
        let l = ls[pos]
        if isDashItem(l.text) { return parseList(&ls, &pos, indent: l.indent, depth: depth) }
        if keyLine(l.text) != nil { return parseMap(&ls, &pos, indent: l.indent, depth: depth) }
        pos += 1
        return parseInline(l.text, depth: depth)
    }

    static func parseList(_ ls: inout [Line], _ pos: inout Int, indent: Int, depth: Int) -> FrontmatterValue? {
        guard depth < maxDepth else { return nil }
        var items: [FrontmatterValue] = []
        while pos < ls.count, ls[pos].indent == indent, isDashItem(ls[pos].text) {
            let text = ls[pos].text
            var k = 1
            while k < text.count, isSpace(text[k]) { k += 1 }
            let rest = Array(text[k...])
            let offset = indent + k
            if rest.isEmpty {
                pos += 1
                if pos < ls.count, ls[pos].indent > indent {
                    guard let v = parseBlock(&ls, &pos, depth: depth + 1) else { return nil }
                    items.append(v)
                } else {
                    items.append(.null)
                }
            } else if isDashItem(rest) {
                ls[pos] = Line(indent: offset, text: rest)
                guard let v = parseList(&ls, &pos, indent: offset, depth: depth + 1) else { return nil }
                items.append(v)
            } else if keyLine(rest) != nil {
                ls[pos] = Line(indent: offset, text: rest)
                guard let v = parseMap(&ls, &pos, indent: offset, depth: depth + 1) else { return nil }
                items.append(v)
            } else {
                guard let v = parseInline(rest, depth: depth) else { return nil }
                items.append(v)
                pos += 1
                if pos < ls.count, ls[pos].indent > indent { return nil }
            }
        }
        return .list(items)
    }

    static func parseMap(_ ls: inout [Line], _ pos: inout Int, indent: Int, depth: Int) -> FrontmatterValue? {
        guard depth < maxDepth else { return nil }
        var pairs: [FrontmatterValue.Pair] = []
        while pos < ls.count, ls[pos].indent == indent, let (key, restStart) = keyLine(ls[pos].text) {
            let rest = trim(ls[pos].text[restStart...])
            var value = FrontmatterValue.null
            if rest.isEmpty {
                pos += 1
                if pos < ls.count, ls[pos].indent > indent {
                    guard let v = parseBlock(&ls, &pos, depth: depth + 1) else { return nil }
                    value = v
                } else if pos < ls.count, ls[pos].indent == indent, isDashItem(ls[pos].text) {
                    guard let v = parseList(&ls, &pos, indent: indent, depth: depth + 1) else { return nil }
                    value = v
                }
            } else {
                guard let v = parseInline(rest, depth: depth) else { return nil }
                value = v
                pos += 1
                if pos < ls.count, ls[pos].indent > indent { return nil }
            }
            pairs.append(.init(key, value))
        }
        if pos < ls.count, ls[pos].indent == indent { return nil }
        return .map(pairs)
    }

    // MARK: Block scalars

    /// `|`, `>` with optional chomping/indent indicators.
    static func blockScalarHeader(_ rest: [UInt8]) -> (folded: Bool, chomp: UInt8?)? {
        guard let f = rest.first, f == UInt8(ascii: "|") || f == UInt8(ascii: ">") else { return nil }
        var chomp: UInt8?
        for b in rest.dropFirst() {
            if b == dash || b == UInt8(ascii: "+") { chomp = b }
            else if b < 0x30 || b > 0x39 { return nil }
        }
        return (f == UInt8(ascii: ">"), chomp)
    }

    static func blockScalar(header: (folded: Bool, chomp: UInt8?), lines: [[UInt8]]) -> FrontmatterValue {
        var indent = Int.max
        for l in lines where !l.allSatisfy(isSpace) {
            var n = 0
            while n < l.count, isSpace(l[n]) { n += 1 }
            indent = min(indent, n)
        }
        if indent == Int.max { indent = 0 }
        var texts: [String] = lines.map { l in
            var n = 0
            while n < min(indent, l.count), isSpace(l[n]) { n += 1 }
            let stripped = Array(l[n...])
            return stripped.allSatisfy(isSpace) ? "" : string(stripped)
        }
        var trailing = 0
        while let last = texts.last, last.isEmpty { texts.removeLast(); trailing += 1 }
        var body: String
        if header.folded {
            body = ""
            var prevBlank = false
            for (idx, t) in texts.enumerated() {
                if t.isEmpty { body += "\n"; prevBlank = true; continue }
                if idx > 0, !prevBlank { body += " " }
                body += t
                prevBlank = false
            }
        } else {
            body = texts.joined(separator: "\n")
        }
        if !texts.isEmpty {
            if header.chomp == UInt8(ascii: "+") { body += String(repeating: "\n", count: 1 + trailing) }
            else if header.chomp != dash { body += "\n" }
        }
        return .string(body)
    }

    // MARK: Rendering

    static func renderNumber(_ d: Double) -> String {
        guard d.isFinite else { return "null" }
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }

    static func renderDoubleQuoted(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 || u.value == 0x7F {
                    let h = String(u.value, radix: 16, uppercase: true)
                    out += "\\u" + String(repeating: "0", count: 4 - h.count) + h
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }

    /// Plain form when it survives a round trip unchanged, otherwise double-quoted.
    static func renderString(_ s: String, flow: Bool, isKey: Bool = false) -> String {
        plainSafe(s, flow: flow, isKey: isKey) ? s : renderDoubleQuoted(s)
    }

    static func plainSafe(_ s: String, flow: Bool, isKey: Bool) -> Bool {
        let b = Array(s.utf8)
        guard let f = b.first, let l = b.last, !isSpace(f), !isSpace(l) else { return false }
        if "-?:,[]{}#&*!|>'\"%@`".utf8.contains(f) { return false }
        for (i, c) in b.enumerated() {
            if c < 0x20 || c == 0x7F { return false }
            if c == colon, i + 1 == b.count || b[i + 1] == space { return false }
            if c == hash, i > 0, isSpace(b[i - 1]) { return false }
            if flow, c == comma || c == lbracket || c == rbracket || c == lbrace || c == rbrace { return false }
        }
        if isKey { return true }
        return resolvePlain(b) == .string(s)
    }

    static func renderInline(_ v: FrontmatterValue, flow: Bool) -> String {
        switch v {
        case .null: "null"
        case .bool(let b): b ? "true" : "false"
        case .number(let d): renderNumber(d)
        case .date(let d): d.iso
        case .dateTime(let d): d.iso
        case .string(let s): renderString(s, flow: flow)
        case .list(let items):
            "[" + items.map { renderInline($0, flow: true) }.joined(separator: ", ") + "]"
        case .map(let pairs):
            "{" + pairs.map { renderString($0.key, flow: true, isKey: true) + ": " + renderInline($0.value, flow: true) }
                .joined(separator: ", ") + "}"
        }
    }
}
