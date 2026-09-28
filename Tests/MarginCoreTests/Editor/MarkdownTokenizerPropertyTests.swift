import Testing
@testable import MarginCore

/// M6-02.B property test: after every random edit the incremental result equals a full
/// tokenization of the new text.
@Suite struct MarkdownTokenizerPropertyTests {
    /// Fragments that stress block state: fences, frontmatter, tables, quotes, lists, CRLF, emoji.
    static let fragments: [String] = [
        "\n", "\n", "\n", "\r\n", "\n\n", " ", "  ", "    ", "\t", "a", "word ", "text ", "x", "é", "😀", "|",
        "```\n", "```swift\n", "~~~\n", "````\n", "```", "`", "``", "---\n", "...\n", "---", "***\n", "- - -\n",
        "# ", "## ", "#tag ", "# H\n", "> ", "> [!note]\n", "> [!warning] T\n", ">", "- ", "* ", "1. ", "2) ",
        "- [ ] ", "- [x] ", "[ ]", "[x]", "@Tue ", "@today", "@ 2026-10-02 ", "^t-4f2a", " ^id", "**", "*", "_", "~~",
        "***", "[[", "]]", "[[Note|alias]]", "[[N#H]]", "![[img.png]]", "[a](b)", "](", "[", "]", "(", ")",
        "| a | b |\n", "|---|---|\n", "| 1 | 2 |\n", "a | b\n", "--- | ---\n", "\\", "\u{FEFF}",
    ]

    static let seeds: [String] = tokenizerCases.map(\.input) + [
        "---\ntitle: T\n---\n# Heading\n\n- [ ] task @Tue ^t-1\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```swift\nlet x = 1\n```\n> [!note] N\n> body\n",
        "",
    ]

    static func randomEdit(_ rng: inout SplitMix64, length: Int) -> (TextRange, String) {
        let loc = Int.random(in: 0...length, using: &rng)
        let maxDel = min(length - loc, Int.random(in: 0...3, using: &rng) == 0 ? 12 : 2)
        let del = Int.random(in: 0...maxDel, using: &rng)
        var repl = ""
        let parts = Int.random(in: 0...3, using: &rng)
        for _ in 0..<parts { repl += fragments.randomElement(using: &rng)! }
        return (TextRange(location: loc, length: del), repl)
    }

    @Test func incrementalEqualsFullOn2000SeededEdits() {
        var rng = SplitMix64(seed: 0xA11CE)
        var edits = 0
        var fullRetokenizes = 0
        var totalLines = 0
        var totalRetokenized = 0
        for sequence in 0..<50 {
            var tk = MarkdownTokenizer(text: Self.seeds[sequence % Self.seeds.count])
            for step in 0..<40 {
                let (range, repl) = Self.randomEdit(&rng, length: tk.utf16Count)
                let before = tk.string
                let update = tk.update(edit: range, replacement: repl)
                edits += 1
                if update.wasFullRetokenize { fullRetokenizes += 1 }
                totalLines += tk.lineCount
                totalRetokenized += update.retokenizedLines.count

                let fresh = MarkdownTokenizer(text: tk.string)
                let ok = tk.tokens == fresh.tokens
                    && tk.blockModel() == fresh.blockModel()
                    && tk.lineCount == fresh.lineCount
                    && (0..<tk.lineCount).allSatisfy { tk.lineRange($0) == fresh.lineRange($0) }
                if !ok {
                    Issue.record("""
                        mismatch at sequence \(sequence) step \(step)
                        before: \(before.debugDescription)
                        edit: \(range) -> \(repl.debugDescription)
                        after: \(tk.string.debugDescription)
                        """)
                    return
                }
            }
        }
        #expect(edits == 2000)
        print("property: \(edits) edits, \(fullRetokenizes) full retokenizes, "
            + "avg retokenized lines \(Double(totalRetokenized) / Double(edits)) of avg \(totalLines / edits) lines")
    }

    @Test func incrementalEqualsFullOnTypingSessions() {
        // Character-by-character typing of a whole document, then deleting it again.
        let doc = Self.seeds[Self.seeds.count - 2]
        var tk = MarkdownTokenizer()
        var typed = 0
        for u in doc.utf16 {
            tk.update(edit: TextRange(location: tk.utf16Count, length: 0),
                      replacement: String(decoding: [u], as: UTF16.self))
            typed += 1
            if typed % 7 == 0 { #expect(tk.tokens == MarkdownTokenizer(text: tk.string).tokens) }
        }
        #expect(tk.string == doc)
        #expect(tk.tokens == MarkdownTokenizer(text: doc).tokens)
        while tk.utf16Count > 0 {
            tk.update(edit: TextRange(location: tk.utf16Count - 1, length: 1), replacement: "")
            if tk.utf16Count % 11 == 0 { #expect(tk.tokens == MarkdownTokenizer(text: tk.string).tokens) }
        }
        #expect(tk.tokens.isEmpty)
    }
}
