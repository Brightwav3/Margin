import Foundation

/// Portable inverted index with BM25 ranking (M10-01). No dependencies; identical on every
/// platform. Field weights: title/aliases 5, headings 2.5, tags 2, body 1 (BM25F-style: weighted
/// term frequencies are summed before the BM25 saturation).
public final class InMemoryFullTextIndex: FullTextIndex, @unchecked Sendable {
    static let k1 = 1.2
    static let b = 0.75
    static let titleWeight = 5.0
    static let headingWeight = 2.5
    static let tagWeight = 2.0
    static let bodyWeight = 1.0
    /// Matches on a longer word that only starts with the typed prefix count a bit less.
    static let prefixFactor = 0.7

    private struct Doc {
        var id: String
        var terms: [String]
        var length: Int
        var foldedTitle: String
    }

    private let lock = NSLock()
    private var docs: [Doc?] = []
    private var slotOf: [String: Int] = [:]
    private var freeSlots: [Int] = []
    /// term -> (slot -> weighted term frequency)
    private var postings: [String: [Int: Double]] = [:]
    private var sortedTerms: [String] = []
    private var termsDirty = false
    private var totalLength = 0

    public init() {}

    public var count: Int { lock.withLock { slotOf.count } }

    public func contains(id: String) -> Bool { lock.withLock { slotOf[id] != nil } }

    public func upsert(_ document: FullTextDocument) {
        // Tokenise outside the lock; it is the expensive part.
        var weighted: [String: Double] = [:]
        var length = 0
        func add(_ text: String, _ weight: Double) {
            for t in SearchTokenizer.terms(in: text) { weighted[t, default: 0] += weight; length += 1 }
        }
        add(document.title, Self.titleWeight)
        for a in document.aliases { add(a, Self.titleWeight) }
        for h in document.headings { add(h, Self.headingWeight) }
        for t in document.tags { add(t, Self.tagWeight) }
        add(document.body, Self.bodyWeight)
        let folded = SearchTokenizer.fold(document.title)

        lock.withLock {
            removeLocked(id: document.id)
            let slot = freeSlots.popLast() ?? { docs.append(nil); return docs.count - 1 }()
            docs[slot] = Doc(id: document.id, terms: Array(weighted.keys), length: length, foldedTitle: folded)
            slotOf[document.id] = slot
            totalLength += length
            for (term, w) in weighted {
                if postings[term] == nil { termsDirty = true }
                postings[term, default: [:]][slot] = w
            }
        }
    }

    public func remove(id: String) { lock.withLock { removeLocked(id: id) } }

    public func removeAll() {
        lock.withLock {
            docs = []; slotOf = [:]; freeSlots = []; postings = [:]; sortedTerms = []
            termsDirty = false; totalLength = 0
        }
    }

    private func removeLocked(id: String) {
        guard let slot = slotOf[id], let doc = docs[slot] else { return }
        for t in doc.terms {
            postings[t]?[slot] = nil
            if postings[t]?.isEmpty == true { postings[t] = nil; termsDirty = true }
        }
        totalLength -= doc.length
        docs[slot] = nil
        slotOf[id] = nil
        freeSlots.append(slot)
    }

    public func search(_ query: FullTextQuery, limit: Int, allowing: (@Sendable (String) -> Bool)?) -> [FullTextMatch] {
        guard !query.terms.isEmpty, limit > 0 else { return [] }
        return lock.withLock {
            let n = Double(slotOf.count)
            guard n > 0 else { return [] }
            if termsDirty { sortedTerms = postings.keys.sorted(); termsDirty = false }
            let avg = max(1, Double(totalLength) / n)

            // Per query word: slot -> best score over the words it stands for.
            var perWord: [[Int: Double]] = []
            for (i, word) in query.terms.enumerated() {
                let isPrefix = query.lastIsPrefix && i == query.terms.count - 1
                var scores: [Int: Double] = [:]
                for term in expansions(of: word, prefix: isPrefix) {
                    guard let list = postings[term] else { continue }
                    let df = Double(list.count)
                    let idf = log(1 + (n - df + 0.5) / (df + 0.5))
                    let factor = term == word ? 1.0 : Self.prefixFactor
                    for (slot, wtf) in list {
                        guard let doc = docs[slot] else { continue }
                        let norm = Self.k1 * (1 - Self.b + Self.b * Double(doc.length) / avg)
                        let s = factor * idf * wtf * (Self.k1 + 1) / (wtf + norm)
                        if s > (scores[slot] ?? 0) { scores[slot] = s }
                    }
                }
                if scores.isEmpty { return [] }
                perWord.append(scores)
            }

            perWord.sort { $0.count < $1.count }
            let joined = query.terms.joined(separator: " ")
            var matches: [FullTextMatch] = []
            outer: for (slot, first) in perWord[0] {
                guard let doc = docs[slot] else { continue }
                if let allowing, !allowing(doc.id) { continue }
                var score = first
                for other in perWord.dropFirst() {
                    guard let s = other[slot] else { continue outer }
                    score += s
                }
                if doc.foldedTitle == joined { score *= 1.5 } else if doc.foldedTitle.hasPrefix(joined) { score *= 1.2 }
                matches.append(FullTextMatch(id: doc.id, score: score))
            }
            matches.sort { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
            return Array(matches.prefix(limit))
        }
    }

    /// The indexed words a query word stands for: itself, and for a prefix every word it starts.
    private func expansions(of word: String, prefix: Bool) -> [String] {
        guard prefix else { return [word] }
        var lo = 0, hi = sortedTerms.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedTerms[mid] < word { lo = mid + 1 } else { hi = mid }
        }
        var out: [String] = []
        while lo < sortedTerms.count, sortedTerms[lo].hasPrefix(word) { out.append(sortedTerms[lo]); lo += 1 }
        return out
    }
}
