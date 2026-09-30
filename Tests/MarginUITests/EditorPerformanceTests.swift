import AppKit
import MarginCore
import Testing
@testable import MarginUI

/// Budget M6-16: typing in a 10 000-word note restyles in under 8 ms per key.
@MainActor @Suite struct EditorPerformanceTests {
    @Test func keystrokeInATenThousandWordNoteStaysUnderBudget() {
        var lines: [String] = ["# Big note", ""]
        var words = 0
        var i = 0
        while words < 10_000 {
            let line = i % 7 == 0 ? "## Section \(i)" : i % 5 == 0 ? "- [ ] Task \(i) with [[Link \(i)]] and **bold** text"
                : "Paragraph \(i) about membranes, osmosis and the fluid mosaic model of the cell."
            lines.append(line)
            words += line.split(separator: " ").count
            i += 1
        }
        let text = lines.joined(separator: "\n")
        let storage = NSTextStorage(string: text)
        var tokenizer = MarkdownTokenizer(text: text)
        MarkdownStyler.apply(to: storage, range: NSRange(location: 0, length: storage.length), tokens: tokenizer.tokens,
                             mode: .live, active: nil)
        let at = (text as NSString).length / 2
        var worst: Duration = .zero
        let clock = ContinuousClock()
        for k in 0..<50 {
            let t = clock.measure {
                let loc = at + k
                storage.replaceCharacters(in: NSRange(location: loc, length: 0), with: "x")
                let update = tokenizer.update(edit: MarkdownRange(location: loc, length: 0), replacement: "x")
                let r = (storage.string as NSString).lineRange(for: NSRange(location: update.changedRange.location,
                                                                            length: update.changedRange.length))
                let tokens = tokenizer.tokens(in: MarkdownRange(location: r.location, length: r.length))
                MarkdownStyler.apply(to: storage, range: r, tokens: tokens, mode: .live, active: nil)
            }
            worst = max(worst, t)
        }
        #expect(worst < .milliseconds(8), "worst keystroke \(worst)")
    }
}
