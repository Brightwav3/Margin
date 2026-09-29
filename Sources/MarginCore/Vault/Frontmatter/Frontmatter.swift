/// A lossless model of a note's YAML frontmatter block (`docs/plan/05-vault-spec.md` §2).
///
/// The block is kept as the original text: every top-level entry stores its raw lines (comments,
/// indentation, quoting, line endings). `render()` re-emits them byte for byte; only an entry that
/// is edited through `set` is re-rendered. Unknown keys therefore survive with their order, and
/// malformed text is never lost, it is only reported by `validate()`.
///
/// Parsing rules:
/// - The text must start (after an optional UTF-8 BOM) with a `---` line; the block ends at the
///   next `---` line. Without a closing fence there is no frontmatter and the body is the whole text.
/// - `---` lines after the closing fence belong to the body.
/// - LF and CRLF (also mixed) are preserved per line.
public struct Frontmatter: Sendable, Hashable {
    struct Entry: Sendable, Hashable {
        var key: String
        var raw: String
    }

    enum Segment: Sendable, Hashable {
        case entry(Entry)
        /// Blank lines, comments and anything that is not a recognizable `key:` entry.
        case raw(String)
    }

    var hasBOM: Bool
    var opening: String
    var segments: [Segment]
    var closing: String

    /// An empty frontmatter block (`---\n---\n`).
    public init() {
        hasBOM = false
        opening = "---\n"
        segments = []
        closing = "---\n"
    }

    // MARK: Parse

    /// Splits `text` into frontmatter and body. `render() + body` reproduces `text` exactly.
    public static func parse(_ text: String) -> (frontmatter: Frontmatter?, body: String) {
        let bytes = Array(text.utf8)
        var start = 0
        var bom = false
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bom = true
            start = 3
        }
        let lines = splitLines(bytes, from: start)
        guard let first = lines.first, isFence(bytes, first) else { return (nil, text) }
        guard let close = lines.indices.dropFirst().first(where: { isFence(bytes, lines[$0]) }) else {
            return (nil, text)
        }

        var fm = Frontmatter()
        fm.hasBOM = bom
        fm.opening = slice(bytes, first.start, first.end)
        fm.closing = slice(bytes, lines[close].start, lines[close].end)
        fm.segments = segments(bytes, lines: lines[1..<close])
        let body = slice(bytes, lines[close].end, bytes.count)
        return (fm, body)
    }

    private struct LineSpan {
        var start: Int
        var contentEnd: Int
        var end: Int
    }

    private static func slice(_ b: [UInt8], _ lo: Int, _ hi: Int) -> String {
        String(decoding: b[lo..<hi], as: UTF8.self)
    }

    private static func splitLines(_ b: [UInt8], from: Int) -> [LineSpan] {
        var out: [LineSpan] = []
        var start = from
        var i = from
        while i < b.count {
            if b[i] == 0x0A {
                let contentEnd = (i > start && b[i - 1] == 0x0D) ? i - 1 : i
                out.append(LineSpan(start: start, contentEnd: contentEnd, end: i + 1))
                start = i + 1
            }
            i += 1
        }
        if start < b.count { out.append(LineSpan(start: start, contentEnd: b.count, end: b.count)) }
        return out
    }

    private static func content(_ b: [UInt8], _ l: LineSpan) -> [UInt8] { Array(b[l.start..<l.contentEnd]) }

    private static func isFence(_ b: [UInt8], _ l: LineSpan) -> Bool {
        YAMLSubset.trimTrailing(content(b, l)) == [0x2D, 0x2D, 0x2D]
    }

    private static func isBlank(_ c: [UInt8]) -> Bool { c.allSatisfy(YAMLSubset.isSpace) }

    private static func segments(_ b: [UInt8], lines: ArraySlice<LineSpan>) -> [Segment] {
        var out: [Segment] = []
        let ls = Array(lines)
        var i = 0
        func appendRaw(_ lo: Int, _ hi: Int) {
            let text = slice(b, lo, hi)
            if case .raw(let prev)? = out.last {
                out[out.count - 1] = .raw(prev + text)
            } else {
                out.append(.raw(text))
            }
        }
        while i < ls.count {
            let c = content(b, ls[i])
            guard let (key, _) = YAMLSubset.keyLine(c) else {
                appendRaw(ls[i].start, ls[i].end)
                i += 1
                continue
            }
            var end = i + 1
            var k = i + 1
            scan: while k < ls.count {
                let n = content(b, ls[k])
                if let f = n.first, YAMLSubset.isSpace(f) {
                    if isBlank(n) { k += 1 } else { k += 1; end = k }
                } else if n.isEmpty || n.first == YAMLSubset.hash {
                    k += 1
                } else if YAMLSubset.isDashItem(n) {
                    k += 1
                    end = k
                } else {
                    break scan
                }
            }
            out.append(.entry(Entry(key: key, raw: slice(b, ls[i].start, ls[end - 1].end))))
            i = end
        }
        return out
    }

    // MARK: Render

    /// The frontmatter block exactly as it will be written (BOM, fences, entries).
    public func render() -> String {
        var out = hasBOM ? "\u{FEFF}" : ""
        out += opening
        for s in segments {
            switch s {
            case .entry(let e): out += e.raw
            case .raw(let r): out += r
            }
        }
        return out + closing
    }

    /// The whole file: the block followed by `body`.
    public func render(body: String) -> String { render() + body }

    // MARK: Lookup

    /// Top-level keys in file order (duplicates repeated).
    public var keys: [String] { entries.map(\.key) }

    private var entries: [Entry] {
        segments.compactMap { if case .entry(let e) = $0 { e } else { nil } }
    }

    public func contains(_ key: String) -> Bool { entries.contains { $0.key == key } }

    /// The typed value of the first entry named `key`; `nil` when absent or malformed.
    public func value(for key: String) -> FrontmatterValue? {
        guard let e = entries.first(where: { $0.key == key }) else { return nil }
        return Self.parseValue(e.raw)
    }

    public func string(for key: String) -> String? { value(for: key)?.stringValue }
    public func number(for key: String) -> Double? { value(for: key)?.numberValue }
    public func bool(for key: String) -> Bool? { value(for: key)?.boolValue }
    public func date(for key: String) -> LocalDate? { value(for: key)?.dateValue }
    public func list(for key: String) -> [FrontmatterValue]? { value(for: key)?.listValue }
    public func map(for key: String) -> [FrontmatterValue.Pair]? { value(for: key)?.mapValue }

    /// `frontmatter["key"]` reads a value; assigning `nil` removes the key.
    public subscript(key: String) -> FrontmatterValue? {
        get { value(for: key) }
        set {
            if let newValue { set(key, newValue) } else { remove(key) }
        }
    }

    // MARK: Mutation

    /// Sets `key`. An existing entry is re-rendered in place (position kept, trailing comment kept
    /// when safe); a new key is appended after the last entry. All other text is untouched.
    public mutating func set(_ key: String, _ value: FrontmatterValue) {
        let defaultNL = opening.utf8.contains(0x0D) ? "\r\n" : "\n"
        var lines = Self.renderEntry(key: key, value: value)
        guard let idx = segments.firstIndex(where: { if case .entry(let e) = $0 { e.key == key } else { false } }),
              case .entry(var old) = segments[idx]
        else {
            segments.append(.entry(Entry(key: key, raw: lines.joined(separator: defaultNL) + defaultNL)))
            return
        }
        let raw = Array(old.raw.utf8)
        let term: String = raw.last == 0x0A ? (raw.count > 1 && raw[raw.count - 2] == 0x0D ? "\r\n" : "\n") : defaultNL
        if lines.count == 1, Self.commentPreservable(value), let c = Self.trailingComment(raw) {
            lines[0] += c
        }
        old.raw = lines.joined(separator: term) + term
        segments[idx] = .entry(old)
    }

    /// Removes every entry named `key`. Returns whether anything was removed.
    @discardableResult
    public mutating func remove(_ key: String) -> Bool {
        let before = segments.count
        segments.removeAll { if case .entry(let e) = $0 { e.key == key } else { false } }
        return segments.count != before
    }

    // MARK: Validation

    /// Problems found in the block, as `MarginError.invalid`. Never modifies or loses text.
    public func validate() -> [MarginError] {
        var problems: [MarginError] = []
        var seen = Set<String>()
        for s in segments {
            switch s {
            case .entry(let e):
                if !seen.insert(e.key).inserted {
                    problems.append(.invalid("Frontmatter key '\(e.key)' is duplicated."))
                }
                if Self.parseValue(e.raw) == nil {
                    problems.append(.invalid("Frontmatter key '\(e.key)' has a malformed value."))
                }
            case .raw(let r):
                for line in r.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
                    let t = line.drop(while: { $0 == " " || $0 == "\t" })
                    if !t.isEmpty, !t.hasPrefix("#") {
                        problems.append(.invalid("Frontmatter line is not a 'key: value' entry: \(t.prefix(40))"))
                    }
                }
            }
        }
        return problems
    }

    public var isValid: Bool { validate().isEmpty }

    // MARK: Entry values

    private static func parseValue(_ raw: String) -> FrontmatterValue? {
        let bytes = Array(raw.utf8)
        let lines = splitLines(bytes, from: 0)
        guard let first = lines.first, let (_, restStart) = YAMLSubset.keyLine(content(bytes, first)) else {
            return nil
        }
        let firstContent = content(bytes, first)
        var rest = Array(firstContent[restStart...])
        if let cs = YAMLSubset.commentStart(rest) { rest = Array(rest[0..<cs]) }
        rest = YAMLSubset.trim(rest[...])
        let tail = lines.dropFirst().map { content(bytes, $0) }

        if !rest.isEmpty {
            if let header = YAMLSubset.blockScalarHeader(rest) {
                return YAMLSubset.blockScalar(header: header, lines: tail)
            }
            for l in tail where !isBlank(l) && YAMLSubset.trim(l[...]).first != YAMLSubset.hash { return nil }
            return YAMLSubset.parseInline(rest)
        }
        guard var ls = YAMLSubset.logicalLines(tail) else { return nil }
        if ls.isEmpty { return .null }
        var pos = 0
        guard let v = YAMLSubset.parseBlock(&ls, &pos, depth: 0), pos == ls.count else { return nil }
        return v
    }

    private static func renderEntry(key: String, value: FrontmatterValue) -> [String] {
        let k = YAMLSubset.renderString(key, flow: false, isKey: true)
        switch value {
        case .list(let items) where !items.isEmpty:
            return [k + ":"] + items.map { "  - " + YAMLSubset.renderInline($0, flow: false) }
        case .map(let pairs) where !pairs.isEmpty:
            return [k + ":"] + pairs.map {
                "  " + YAMLSubset.renderString($0.key, flow: false, isKey: true) + ": "
                    + YAMLSubset.renderInline($0.value, flow: false)
            }
        default:
            return [k + ": " + YAMLSubset.renderInline(value, flow: false)]
        }
    }

    /// Whitespace + `# comment` of a single-line entry, `nil` otherwise.
    private static func trailingComment(_ raw: [UInt8]) -> String? {
        let lines = splitLines(raw, from: 0)
        guard lines.count == 1, let (_, restStart) = YAMLSubset.keyLine(content(raw, lines[0])) else { return nil }
        let c = content(raw, lines[0])
        let rest = Array(c[restStart...])
        guard var cs = YAMLSubset.commentStart(rest) else { return nil }
        while cs > 0, YAMLSubset.isSpace(rest[cs - 1]) { cs -= 1 }
        return String(decoding: rest[cs...], as: UTF8.self)
    }

    /// A comment may follow the new value only if it cannot be swallowed by a plain scalar.
    private static func commentPreservable(_ value: FrontmatterValue) -> Bool {
        switch value {
        case .null, .bool, .number, .date, .dateTime: true
        case .string: YAMLSubset.renderInline(value, flow: false).hasPrefix("\"")
        case .list(let l): l.isEmpty
        case .map(let m): m.isEmpty
        }
    }
}
