import Foundation
@testable import MarginCore

/// A generated vault of study notes (Czech and English words, with diacritics) for search tests.
enum SearchCorpus {
    static let words = [
        "mitóza", "meióza", "buňka", "jádro", "membrána", "enzym", "bílkovina", "ribozom", "organela", "chromozom",
        "derivace", "integrál", "limita", "posloupnost", "matice", "vektor", "determinant", "funkce", "řada", "konvergence",
        "entropy", "enthalpy", "reaction", "catalyst", "molecule", "orbital", "bond", "solvent", "titration", "equilibrium",
        "algorithm", "recursion", "graph", "tree", "complexity", "hash", "queue", "stack", "sorting", "pointer",
        "history", "empire", "treaty", "revolution", "census", "trade", "policy", "market", "demand", "supply",
    ]
    static let courses = ["bio", "math", "chem", "cs", "hist"]

    /// `(path, content)` pairs for `count` notes, `<semester>/<course>/<title>.md`.
    static func entries(count: Int, seed: UInt64 = 7) -> [(path: String, content: String)] {
        var rng = SplitMix64(seed: seed)
        var out: [(path: String, content: String)] = []
        for i in 0..<count {
            let course = courses[i % courses.count]
            let title = "\(words[Int(rng.next() % UInt64(words.count))].capitalized) \(words[Int(rng.next() % UInt64(words.count))]) \(i)"
            var body = "# \(title)\n\n"
            for p in 0..<4 {
                if p == 2 { body += "## \(words[Int(rng.next() % UInt64(words.count))].capitalized) section\n\n" }
                body += (0..<40).map { _ in words[Int(rng.next() % UInt64(words.count))] }.joined(separator: " ") + ".\n\n"
            }
            let kind = ["lecture", "lab", "seminar", "note"][i % 4]
            let day = 1 + i % 28
            let content = """
            ---
            id: n-\(i)
            type: \(kind)
            date: 2026-10-\(String(format: "%02d", day))
            tags: [\(words[i % words.count]), exam]
            ---
            \(body)
            """
            out.append(("fall-2026/\(course)/\(title).md", content))
        }
        return out
    }

    static func documents(count: Int, seed: UInt64 = 7) -> [FullTextDocument] {
        entries(count: count, seed: seed).map { e in
            let (fm, body) = Frontmatter.parse(e.content)
            let title = e.path.split(separator: "/").last.map { String($0.dropLast(3)) } ?? e.path
            return FullTextDocument(id: e.path, title: title, headings: ["\(title)"], tags: fm?.tags ?? [], body: body)
        }
    }
}
