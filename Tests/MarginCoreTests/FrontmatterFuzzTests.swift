import Testing
@testable import MarginCore

/// Deterministic SplitMix64 so every fuzz run is reproducible.
private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { int(100) < percent }
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
}

private let words = [
    "date", "class", "type", "session", "tags", "due", "weight", "id", "name", "code", "room",
    "žluťoučký", "kůň", "🎓", "a b", "x-y", "x_y", "Key", "1", "true", "日本語", "dotted.key", "a:b",
]
private let nastyStrings = [
    "", " ", "a b", "[[X]]", "[[Cell Biology]]", "#x", "a: b", "- x", "true", "null", "123", "1e5",
    "2026-09-24", "2026-09-24T10:00", "multi\nline", "quote\"s", "it's", "tab\t", "žluťoučký kůň",
    "emoji 🎓", ",", "{a}", "a #b", "%", "&x", "*y", "! t", "|", ">", "  lead", "trail  ", "\\", "~",
    "---", "...", "a:", ":a", "cr\rlf", "25%", "Tue", "10:00", "é", "e\u{301}", "\u{2028}", "x]y", "'", "\"",
]

private func randomWord(_ r: inout SplitMix64) -> String {
    r.chance(75) ? r.pick(words) : String((0..<(1 + r.int(6))).map { _ in
        r.pick(Array("abcdefghijklmnopqrstuvwxyzÁéß0123456789 _-:#[]{}\"'".map { $0 }))
    })
}

private func randomDate(_ r: inout SplitMix64) -> LocalDate {
    LocalDate(year: 2020 + r.int(10), month: 1 + r.int(12), day: 1 + r.int(28))!
}

private func randomValue(_ r: inout SplitMix64, depth: Int = 0) -> FrontmatterValue {
    let kinds = depth >= 2 ? 7 : 9
    switch r.int(kinds) {
    case 0: return .null
    case 1: return .bool(r.chance(50))
    case 2: return .number(r.chance(50) ? Double(r.int(2000) - 1000) : Double(r.int(100_000)) / 64.0 - 700)
    case 3, 4: return .string(r.chance(70) ? r.pick(nastyStrings) : randomWord(&r))
    case 5: return .date(randomDate(&r))
    case 6:
        return .dateTime(LocalDateTime(date: randomDate(&r), time: LocalTime(string: "\(String(format: "%02d", r.int(24))):\(String(format: "%02d", r.int(60)))")!))
    case 7: return .list((0..<r.int(4)).map { _ in randomValue(&r, depth: depth + 1) })
    default:
        return .map((0..<r.int(4)).map { _ in .init(randomWord(&r), randomValue(&r, depth: depth + 1)) })
    }
}

/// Renders a hand-styled scalar the way people write them (quoting, comments, odd spacing).
private func styledScalar(_ r: inout SplitMix64) -> String {
    switch r.int(14) {
    case 0: return "plain text"
    case 1: return "\"double \\\"quoted\\\" \\u00e9\""
    case 2: return "'single ''quoted'''"
    case 3: return String(r.int(500))
    case 4: return "\(r.int(90)).\(r.int(9))"
    case 5: return r.pick(["true", "false", "yes", "~", "null", ""])
    case 6: return randomDate(&r).iso
    case 7: return "\(randomDate(&r).iso)T10:\(String(format: "%02d", r.int(60)))"
    case 8: return "\"[[Cell Biology]]\""
    case 9: return "[[Cell Biology]]"
    case 10: return "25%"
    case 11: return r.pick(nastyStrings)
    case 12: return "žluťoučký 🎓 kůň"
    default: return "value with # not a comment"
    }
}

private func randomEntry(_ r: inout SplitMix64) -> String {
    let key = r.chance(85) ? r.pick(words) : (r.chance(50) ? "\"quoted key\"" : "'sq key'")
    let space = r.pick(["", " ", "  ", "   "])
    let comment = r.chance(25) ? r.pick(["  # note", " #x", "\t# tab", "   # a: b"]) : ""
    switch r.int(9) {
    case 0, 1, 2:
        return "\(key):\(space.isEmpty ? " " : space)\(styledScalar(&r))\(comment)"
    case 3:
        let items = (0..<(1 + r.int(4))).map { _ in styledScalar(&r) }
        return "\(key): [\(items.joined(separator: r.pick([",", ", ", " , "])))]\(comment)"
    case 4, 5:
        let indent = r.pick(["  ", "    ", ""])
        let items = (0..<(1 + r.int(4))).map { _ -> String in
            let c = r.chance(15) ? "  # c" : ""
            let mid = r.chance(10) ? "\n\(indent)# inner comment" : ""
            return "\(indent)- \(styledScalar(&r))\(c)\(mid)"
        }
        return "\(key):\(comment)\n" + items.joined(separator: "\n")
    case 6:
        let items = (0..<(1 + r.int(3))).map { _ in
            "  - {day: Tue, time: \"10:00\", length: 1.5, kind: Lecture, room: \"Sci 204\"\(r.chance(30) ? ", note: x" : "")}"
        }
        return "\(key):\n" + items.joined(separator: "\n")
    case 7:
        return "\(key):\n  sub: \(styledScalar(&r))\n  other:\n    - a\n    - b"
    default:
        return "\(key): |\n  literal line\n  second line"
    }
}

private func randomDocument(_ r: inout SplitMix64) -> String {
    var lines: [String] = []
    for _ in 0..<r.int(9) {
        lines.append(randomEntry(&r))
        if r.chance(15) { lines.append(r.pick(["", "# standalone comment", "   ", "#no space"])) }
        if r.chance(4) { lines.append(r.pick(["garbage line", "  - stray", "]", "\t\ttabbed"])) }
    }
    let crlf = r.chance(30)
    var out = ""
    for l in lines {
        for sub in l.split(separator: "\n", omittingEmptySubsequences: false) {
            out += sub + ((crlf && !r.chance(5)) || (!crlf && r.chance(2)) ? "\r\n" : "\n")
        }
    }
    let nl = crlf ? "\r\n" : "\n"
    var text = (r.chance(10) ? "\u{FEFF}" : "") + "---" + (r.chance(5) ? "  " : "") + nl + out + "---" + (r.chance(90) ? nl : "")
    if r.chance(80) {
        text += r.pick(["# Title\n\nBody text\n", "\n---\n\nrule above\n---\nkey: value\n---\n", "plain", "- [ ] task ^t-1\r\n", "\u{FEFF}bom in body", "---"])
    }
    if r.chance(3) { text = String(text.dropLast(r.int(8))) }
    return text
}

private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

@Suite("Frontmatter fuzz") struct FrontmatterFuzzTests {
    static let count = 10_000

    @Test func parseRenderIsByteIdentical() {
        var r = SplitMix64(seed: 0xF00D_0001)
        var withFrontmatter = 0
        var withEntries = 0
        for i in 0..<Self.count {
            let text = randomDocument(&r)
            let (fm, body) = Frontmatter.parse(text)
            let out = (fm?.render() ?? "") + body
            if bytes(out) != bytes(text) {
                Issue.record("round trip changed input #\(i): \(text.debugDescription) -> \(out.debugDescription)")
                return
            }
            if let fm {
                withFrontmatter += 1
                if !fm.keys.isEmpty { withEntries += 1 }
                _ = fm.validate()
                _ = (fm.date, fm.className, fm.kind, fm.session, fm.tags, fm.due, fm.weight, fm.id)
                for k in fm.keys { _ = fm.value(for: k) }
            } else if bytes(body) != bytes(text) {
                Issue.record("nil frontmatter must return the text untouched (#\(i))")
                return
            }
        }
        #expect(withFrontmatter > Self.count / 2)
        #expect(withEntries > Self.count / 3)
    }

    @Test func setKeyChangesOnlyThatKey() {
        var r = SplitMix64(seed: 0xF00D_0002)
        var checked = 0
        for i in 0..<Self.count {
            let text = randomDocument(&r)
            let (fm, body) = Frontmatter.parse(text)
            guard var f = fm else { continue }
            let before = f
            let existing = before.keys
            let key = (!existing.isEmpty && r.chance(60)) ? r.pick(existing) : randomWord(&r)
            let value = randomValue(&r)
            f.set(key, value)
            let rendered = f.render(body: body)

            let (again, body2) = Frontmatter.parse(rendered)
            guard let g = again else {
                Issue.record("edited document lost its frontmatter (#\(i)): \(rendered.debugDescription)")
                return
            }
            if bytes(body2) != bytes(body) || g.hasBOM != before.hasBOM {
                Issue.record("body or BOM changed (#\(i))")
                return
            }
            if g.value(for: key) != value {
                Issue.record("set \(key.debugDescription) = \(value) not read back (#\(i)): \(rendered.debugDescription); got \(String(describing: g.value(for: key)))")
                return
            }
            // Everything else is byte-identical, in the same order.
            let editedIndex = before.segments.firstIndex { if case .entry(let e) = $0 { e.key == key } else { false } }
            var expected = before.segments
            if let editedIndex { expected.remove(at: editedIndex) }
            var actual = g.segments
            if let editedIndex {
                guard actual.count == before.segments.count else {
                    Issue.record("segment count changed (#\(i))")
                    return
                }
                actual.remove(at: editedIndex)
            } else {
                guard actual.count == expected.count + 1 else {
                    Issue.record("appended key changed segment count (#\(i)): \(rendered.debugDescription)")
                    return
                }
                actual.removeLast()
            }
            if actual != expected {
                Issue.record("other segments changed (#\(i)): \(text.debugDescription) -> \(rendered.debugDescription)")
                return
            }
            // Other keys keep their typed values.
            for k in before.keys where k != key {
                if g.value(for: k) != before.value(for: k) {
                    Issue.record("value of untouched key \(k.debugDescription) changed (#\(i))")
                    return
                }
            }
            // A second render/parse is stable.
            if bytes(g.render(body: body2)) != bytes(rendered) { Issue.record("unstable re-render (#\(i))"); return }
            checked += 1
        }
        #expect(checked > Self.count / 2)
    }

    @Test func removeKeyChangesOnlyThatKey() {
        var r = SplitMix64(seed: 0xF00D_0003)
        for i in 0..<2_000 {
            let text = randomDocument(&r)
            guard var f = Frontmatter.parse(text).frontmatter, let key = f.keys.first else { continue }
            let others = f.keys.filter { $0 != key }
            let untouched = others.map { f.value(for: $0) }
            f.remove(key)
            #expect(!f.contains(key), "#\(i)")
            #expect(f.keys == others, "#\(i)")
            #expect(others.map { f.value(for: $0) } == untouched, "#\(i)")
        }
    }

    @Test func garbageNeverCrashesAndRoundTrips() {
        var r = SplitMix64(seed: 0xF00D_0004)
        let alphabet: [String] = ["---", "\n", "\r\n", "\r", " ", "  ", "\t", ":", ": ", "-", "- ", "#", " #", "[", "]", "{", "}",
                                  ",", "\"", "'", "\\", "\\u00", "\\x", "|", ">", "&", "*", "!", "?", "%", "@", "`", "key", "a", "1",
                                  "2026-09-24", "\u{FEFF}", "é", "🎓", "\u{0}", "\u{7F}", "\u{85}", "\u{2028}", "[[x]]"]
        for i in 0..<Self.count {
            var text = ""
            for _ in 0..<r.int(60) { text += r.pick(alphabet) }
            if r.chance(50) { text = "---\n" + text + (r.chance(70) ? "\n---\nbody" : "") }
            let (fm, body) = Frontmatter.parse(text)
            let out = (fm?.render() ?? "") + body
            if bytes(out) != bytes(text) {
                Issue.record("garbage changed (#\(i)): \(text.debugDescription) -> \(out.debugDescription)")
                return
            }
            if var fm {
                _ = fm.validate()
                for k in fm.keys { _ = fm.value(for: k) }
                _ = (fm.date, fm.className, fm.kind, fm.session, fm.tags, fm.due, fm.weight, fm.id)
                fm.set("date", .date(randomDate(&r)))
                let (again, _) = Frontmatter.parse(fm.render(body: body))
                if again?.date == nil { Issue.record("set on garbage lost (#\(i)): \(text.debugDescription)"); return }
            }
        }
    }

    @Test func valuesRoundTripThroughRendering() {
        var r = SplitMix64(seed: 0xF00D_0005)
        for i in 0..<Self.count {
            let value = randomValue(&r)
            var f = Frontmatter()
            f.set("k", value)
            let g = Frontmatter.parse(f.render()).frontmatter
            if g?.value(for: "k") != value {
                Issue.record("value \(value) (#\(i)) rendered as \(f.render().debugDescription)")
                return
            }
        }
    }
}
