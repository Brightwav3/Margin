import Testing
@testable import MarginCore

/// M6-16.B: incremental tokenization of a 10 000 word document must take < 3 ms per change.
///
/// The budget is asserted strictly only in optimized builds; in debug builds (unoptimized, often
/// inside a Docker container) it is asserted with generous slack and the measured numbers are
/// printed so they can be compared with the budget.
@Suite struct MarkdownTokenizerPerfTests {
    /// About 10 000 words of realistic notes: headings, prose with inline markup, lists, tasks,
    /// tables, quotes and code fences.
    static func makeDocument(words target: Int = 10_000) -> String {
        let vocabulary = ["cell", "membrane", "protein", "transport", "osmosis", "gradient", "lipid", "channel",
                          "diffusion", "energy", "receptor", "signal", "vesicle", "nucleus", "enzyme", "pump"]
        var rng = SplitMix64(seed: 42)
        var text = "---\ntitle: Cell Biology\nclass: \"[[Cell Biology]]\"\ntags:\n  - midterm\n---\n"
        var words = 0
        var section = 0
        func sentence(_ n: Int) -> String {
            var parts: [String] = []
            for i in 0..<n {
                var w = vocabulary.randomElement(using: &rng)!
                switch (i, Int.random(in: 0..<12, using: &rng)) {
                case (_, 0): w = "**\(w)**"
                case (_, 1): w = "*\(w)*"
                case (_, 2): w = "`\(w)`"
                case (_, 3): w = "[[\(w.capitalized)]]"
                case (_, 4): w = "#\(w)"
                default: break
                }
                parts.append(w)
            }
            words += n
            return parts.joined(separator: " ")
        }
        while words < target {
            section += 1
            text += "## Section \(section)\n\n"
            words += 2
            for _ in 0..<3 { text += sentence(45) + ". " + sentence(30) + ".\n\n" }
            text += "- [ ] " + sentence(6) + " @Tue ^t-\(section)\n- [x] " + sentence(5) + "\n- " + sentence(7) + "\n\n"
            if section % 4 == 0 {
                text += "| term | meaning |\n|---|---|\n| \(sentence(1)) | \(sentence(4)) |\n| \(sentence(1)) | \(sentence(4)) |\n\n"
            }
            if section % 5 == 0 { text += "> [!note] Remember\n> " + sentence(12) + "\n\n" }
            if section % 6 == 0 { text += "```swift\nlet value = 1 // \(sentence(3))\n```\n\n" }
        }
        return text
    }

    struct Stats { var mean: Double; var p95: Double; var max: Double }

    static func stats(_ samples: [Double]) -> Stats {
        let sorted = samples.sorted()
        return Stats(mean: samples.reduce(0, +) / Double(samples.count),
                     p95: sorted[Int(Double(sorted.count) * 0.95)], max: sorted.last ?? 0)
    }

    @Test func incrementalUpdateOn10000WordsStaysUnderBudget() {
        let doc = Self.makeDocument()
        let wordCount = doc.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        #expect(wordCount >= 10_000)

        let clock = ContinuousClock()
        let full = clock.measure { _ = MarkdownTokenizer(text: doc) }

        var tk = MarkdownTokenizer(text: doc)
        var rng = SplitMix64(seed: 7)
        var typing: [Double] = [], newlines: [Double] = [], deletes: [Double] = []
        func ms(_ d: Duration) -> Double {
            Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }
        for i in 0..<300 {
            let loc = Int.random(in: 0..<tk.utf16Count, using: &rng)
            switch i % 3 {
            case 0: typing.append(ms(clock.measure { tk.update(edit: TextRange(location: loc, length: 0), replacement: "x") }))
            case 1: newlines.append(ms(clock.measure { tk.update(edit: TextRange(location: loc, length: 0), replacement: "\n") }))
            default: deletes.append(ms(clock.measure { tk.update(edit: TextRange(location: loc, length: 1), replacement: "") }))
            }
        }
        // Editing inside frontmatter and around a fence, the costly-looking cases.
        let fenceEdit = ms(clock.measure {
            tk.update(edit: TextRange(location: NSStringLikeOffset(tk.string, "```swift"), length: 1), replacement: "")
        })
        let all = typing + newlines + deletes
        let s = Self.stats(all)
        let t = Self.stats(typing), n = Self.stats(newlines), d = Self.stats(deletes)
        print("""
            tokenizer perf, \(wordCount) words, \(doc.utf16.count) UTF-16 units, \(tk.lineCount) lines
              full tokenization:   \(ms(full)) ms
              incremental typing:  mean \(t.mean) ms, p95 \(t.p95) ms, max \(t.max) ms
              incremental newline: mean \(n.mean) ms, p95 \(n.p95) ms, max \(n.max) ms
              incremental delete:  mean \(d.mean) ms, p95 \(d.p95) ms, max \(d.max) ms
              fence marker edit:   \(fenceEdit) ms
            """)
        #expect(tk.tokens == MarkdownTokenizer(text: tk.string).tokens)

        #if DEBUG
        let budget = 10.0    // unoptimized build: generous slack, see the printed numbers
        #else
        let budget = 3.0
        #endif
        #expect(s.mean < budget, "mean \(s.mean) ms")
        #expect(s.p95 < budget * 2, "p95 \(s.p95) ms")
    }
}

func NSStringLikeOffset(_ text: String, _ needle: String) -> Int {
    NSStringLike(text: text).offset(of: needle)
}
