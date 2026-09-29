import Foundation

/// One word of a text: its folded form and where it stands in the original string.
struct SearchToken: Sendable, Hashable {
    /// Lowercased, diacritics removed (`Přednáška` -> `prednaska`).
    var term: String
    var range: Range<String.Index>
}

/// Splits text into searchable words. A word is a run of letters and digits; the term is folded
/// (case and diacritics), so `Mitóza`, `mitoza` and `MITOZA` are the same word. Used by every
/// `FullTextIndex` and by the snippet builder, so what matches is also what gets highlighted.
enum SearchTokenizer {
    /// Folded form of one character; ASCII takes the fast path.
    private static func fold(_ ch: Character, cache: inout [Character: String]) -> String {
        if let a = ch.asciiValue {
            return a >= 0x41 && a <= 0x5A ? String(UnicodeScalar(a + 32)) : String(ch)
        }
        if let hit = cache[ch] { return hit }
        let folded = String(ch).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        cache[ch] = folded
        return folded
    }

    static func tokens(in text: String) -> [SearchToken] {
        var out: [SearchToken] = []
        var cache: [Character: String] = [:]
        var start: String.Index?
        var term = ""
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            let next = text.index(after: i)
            if ch.isLetter || ch.isNumber {
                if start == nil { start = i }
                term += fold(ch, cache: &cache)
            } else if let s = start {
                out.append(SearchToken(term: term, range: s..<i))
                start = nil; term = ""
            }
            i = next
        }
        if let s = start { out.append(SearchToken(term: term, range: s..<text.endIndex)) }
        return out
    }

    static func terms(in text: String) -> [String] { tokens(in: text).map(\.term) }

    /// The whole string folded, without touching word boundaries.
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
