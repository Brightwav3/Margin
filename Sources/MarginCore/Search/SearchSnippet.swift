import Foundation

/// Builds the one-line passage of a search hit and the highlight ranges of query words.
enum SearchSnippet {
    static let width = 140
    /// Characters kept in front of the first match.
    static let lead = 40

    /// Whether a folded token is one of the query's words (the last one as a prefix when asked).
    static func matches(_ term: String, _ query: FullTextQuery) -> Bool {
        for (i, word) in query.terms.enumerated() {
            if term == word { return true }
            if query.lastIsPrefix, i == query.terms.count - 1, term.hasPrefix(word) { return true }
        }
        return false
    }

    /// The query words a folded token stands for.
    static func matchedWords(_ term: String, _ query: FullTextQuery) -> [String] {
        var out: [String] = []
        for (i, word) in query.terms.enumerated() {
            if term == word || (query.lastIsPrefix && i == query.terms.count - 1 && term.hasPrefix(word)) { out.append(word) }
        }
        return out
    }

    /// Ranges of the query words in `text`, in `Character` offsets.
    static func highlights(in text: String, query: FullTextQuery) -> [HighlightRange] {
        guard !query.isEmpty else { return [] }
        var out: [HighlightRange] = []
        var offset = 0
        var cursor = text.startIndex
        for token in SearchTokenizer.tokens(in: text) where matches(token.term, query) {
            offset += text.distance(from: cursor, to: token.range.lowerBound)
            let length = text.distance(from: token.range.lowerBound, to: token.range.upperBound)
            out.append(HighlightRange(location: offset, length: length))
            offset += length
            cursor = token.range.upperBound
        }
        return out
    }

    /// A passage of `body` around the best match, or `nil` when no query word occurs in it. The
    /// window starts at the match that has the most distinct query words within reach.
    static func passage(of body: String, query: FullTextQuery) -> (text: String, highlights: [HighlightRange])? {
        guard !query.isEmpty else { return nil }
        // Scan only as far as needed: up to the first place where all query words stand together.
        var tokens: [SearchToken] = []
        var hits: [Int] = []
        let wanted = Set(query.terms)
        SearchTokenizer.scan(body) { t in
            tokens.append(t)
            guard matches(t.term, query) else { return false }
            hits.append(tokens.count - 1)
            guard wanted.count > 1 else { return true }
            var seen = Set<String>()
            for h in hits.reversed() {
                if body.distance(from: tokens[h].range.lowerBound, to: t.range.upperBound) > width { break }
                seen.formUnion(matchedWords(tokens[h].term, query))
            }
            return seen.count == wanted.count
        }
        guard !hits.isEmpty else { return nil }

        var best = hits[0]
        if query.terms.count > 1 {
            var bestCount = 0
            for i in hits.prefix(200) {
                var seen = Set<String>()
                var j = i
                while j < tokens.count, body.distance(from: tokens[i].range.lowerBound, to: tokens[j].range.upperBound) <= width {
                    seen.formUnion(matchedWords(tokens[j].term, query))
                    j += 1
                }
                if seen.count > bestCount { bestCount = seen.count; best = i }
                if bestCount == query.terms.count { break }
            }
        }

        let matchStart = tokens[best].range.lowerBound
        let from = body.index(matchStart, offsetBy: -lead, limitedBy: body.startIndex) ?? body.startIndex
        let to = body.index(from, offsetBy: width, limitedBy: body.endIndex) ?? body.endIndex
        var chars = Array(body[from..<to]).map { $0.isWhitespace ? " " : $0 }
        let cutFront = from != body.startIndex
        let cutBack = to != body.endIndex
        if cutFront, let first = chars.first, first != " ", let before = body[..<from].last, !before.isWhitespace {
            // Drop the partial word at the front unless it is very long.
            if let space = chars.prefix(16).firstIndex(of: " ") { chars.removeFirst(space + 1) }
        }
        if cutBack, let last = chars.last, last != " ", body[to] != " ", !body[to].isWhitespace {
            if let space = chars.suffix(16).lastIndex(of: " ") { chars.removeSubrange(space...) }
        }
        // Blank runs (paragraph breaks) collapse to one space.
        var flat: [Character] = []
        for c in chars where !(c == " " && flat.last == " ") { flat.append(c) }
        while flat.first == " " { flat.removeFirst() }
        while flat.last == " " { flat.removeLast() }
        if flat.isEmpty { return nil }
        var text = String(flat)
        if cutFront { text = "…" + text }
        if cutBack { text += "…" }
        return (text, highlights(in: text, query: query))
    }
}
