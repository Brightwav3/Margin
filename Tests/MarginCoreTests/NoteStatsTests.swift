import Foundation
import Testing
@testable import MarginCore

@Suite struct NoteStatsTests {

    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    private func full(_ text: String) -> NoteTextCounts { NoteStatsTracker.fullCount(text) }

    @Test func countsWordsAndTasksOutsideCode() {
        var tracker = NoteStatsTracker()
        let text = "# Title\n\nsome words here\n\n- [ ] open\n- [x] done\n\n```\n- [ ] code\n```\n"
        let c = tracker.update(body: text)
        #expect(c == NoteTextCounts(words: NoteIndex.wordCount(text), openTasks: 1, totalTasks: 2))
        #expect(NoteStatsCalculator.count(body: text).openTasks == 1)
    }

    @Test func typingInProseKeepsTaskCountsWithoutRescan() {
        var tracker = NoteStatsTracker()
        var text = "# T\n\nfirst paragraph\n\n- [ ] a\n\nsecond paragraph\n"
        tracker.update(body: text)
        for word in ["alpha", "beta", "gamma"] {
            text = text.replacingOccurrences(of: "second paragraph", with: "second paragraph \(word)")
            #expect(tracker.update(body: text) == full(text))
        }
        #expect(!NoteStatsTracker.mayAffectTasks("plain prose line"))
        #expect(NoteStatsTracker.mayAffectTasks("- [ ] task"))
        #expect(NoteStatsTracker.mayAffectTasks("```swift"))
        #expect(NoteStatsTracker.mayAffectTasks(""))
        #expect(NoteStatsTracker.mayAffectTasks("    indented"))
    }

    /// The incremental result equals a full recount after every one of 4000 random edits of a document
    /// full of fences, lists, indentation and tasks.
    @Test func incrementalEqualsFullRecountUnderRandomEdits() {
        var rng = SplitMix64(state: 2026)
        let pieces = [
            "plain words here", "more prose", "- [ ] open task", "- [x] done task", "  - [ ] nested", "    - [ ] indented",
            "```", "~~~", "```swift", "", "", "# Heading", "- item", "1. first", "> quote", "text [[link]] end", "* [ ] star task",
            "    code line", "\t- [x] tabbed", "[ ] not a task", "word", "---",
        ]
        func line() -> String { pieces[rng.below(pieces.count)] }
        var lines = (0..<40).map { _ in line() }
        var tracker = NoteStatsTracker()
        var mismatches = 0
        for step in 0..<4000 {
            switch rng.below(5) {
            case 0: lines[rng.below(lines.count)] = line()
            case 1: lines.insert(line(), at: rng.below(lines.count + 1))
            case 2: if lines.count > 3 { lines.remove(at: rng.below(lines.count)) }
            case 3:   // typing inside a line
                let i = rng.below(lines.count)
                lines[i] += [" x", "y", " word more", "[", "`", " [ ]"][rng.below(6)]
            default:  // replace a small block
                let i = rng.below(lines.count)
                lines.replaceSubrange(i..<min(lines.count, i + 1 + rng.below(3)), with: (0..<rng.below(4)).map { _ in line() })
                if lines.isEmpty { lines = [line()] }
            }
            let text = lines.joined(separator: "\n") + (rng.below(2) == 0 ? "\n" : "")
            let got = tracker.update(body: text)
            if got != full(text) {
                mismatches += 1
                Issue.record("step \(step): \(got) != \(full(text))")
                if mismatches > 3 { return }
            }
        }
        #expect(mismatches == 0)
    }
}
