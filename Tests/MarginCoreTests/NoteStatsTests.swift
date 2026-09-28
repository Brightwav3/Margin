import Foundation
import Testing
@testable import MarginCore

@Suite struct NoteStatsTests {
    #if DEBUG
    static let slack = 5.0
    #else
    static let slack = 1.0
    #endif

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

    /// M6-08: the inspector numbers follow typing within 200 ms on a 10 000 word note.
    @Test func updateOnATenThousandWordNoteIsFast() {
        var rng = SplitMix64(state: 5)
        let words = ["cell", "membrane", "protein", "energy", "atom", "bond", "the", "of", "and", "reaction"]
        var lines: [String] = ["# Long note", ""]
        var total = 0
        while total < 10_000 {
            let n = 10 + rng.below(30)
            lines.append((0..<n).map { _ in words[rng.below(words.count)] }.joined(separator: " "))
            total += n
            if lines.count % 12 == 0 { lines.append("- [ ] task \(lines.count)") }
            if lines.count % 7 == 0 { lines.append("") }
        }
        var tracker = NoteStatsTracker()
        let text0 = lines.joined(separator: "\n")
        func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }

        let t0 = ContinuousClock.now
        let first = tracker.update(body: text0)
        let cold = seconds(ContinuousClock.now - t0)
        #expect(first.words >= 10_000)

        // Typing: one word appended to a middle paragraph, many times.
        var worstType = 0.0
        var edited = lines
        let middle = edited.count / 2 + 1
        for i in 0..<50 {
            edited[middle] += " typed\(i)"
            let text = edited.joined(separator: "\n")
            let t = ContinuousClock.now
            let c = tracker.update(body: text)
            worstType = max(worstType, seconds(ContinuousClock.now - t))
            #expect(c.words == first.words + i + 1)
        }
        // Worst case for the incremental path: an edit that forces a task rescan.
        edited[middle + 1] = "- [ ] a new task"
        let t1 = ContinuousClock.now
        let rescan = tracker.update(body: edited.joined(separator: "\n"))
        let rescanTime = seconds(ContinuousClock.now - t1)
        #expect(rescan.totalTasks == first.totalTasks + 1)

        print("NoteStats on \(first.words) words (slack x\(Self.slack)): cold \(Int(cold * 1000)) ms, "
              + "typing update worst \(String(format: "%.1f", worstType * 1000)) ms, task rescan \(Int(rescanTime * 1000)) ms")
        #expect(cold < 0.2 * Self.slack && worstType < 0.2 * Self.slack && rescanTime < 0.2 * Self.slack)
    }
}
