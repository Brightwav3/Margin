import Foundation
import Testing
@testable import MarginCore

extension PerfSuites {
@Suite struct NoteStatsPerfTests {
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

    /// M6-08: the inspector numbers follow typing within 200 ms on a 10 000 word note.
    /// One run = cold count + 50 typing updates + one task rescan on a fresh tracker; the budget is
    /// asserted on the median of `perfRuns` runs (after a warm-up run) for each of the three figures.
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
        let text0 = lines.joined(separator: "\n")
        func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }

        var colds: [Double] = [], typings: [Double] = [], rescans: [Double] = []
        for run in 0...perfRuns {
            var tracker = NoteStatsTracker()
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
            if run > 0 { colds.append(cold * 1000); typings.append(worstType * 1000); rescans.append(rescanTime * 1000) }
        }

        let cold = perfMedian(colds), typing = perfMedian(typings), rescan = perfMedian(rescans)
        print("NoteStats on 10000 words (slack x\(Self.slack), median of \(perfRuns) runs): cold \(String(format: "%.1f", cold)) ms [\(perfList(colds))], "
              + "typing update worst \(String(format: "%.1f", typing)) ms [\(perfList(typings))], task rescan \(String(format: "%.1f", rescan)) ms [\(perfList(rescans))]")
        let budget = 200 * Self.slack
        #expect(cold < budget, "cold \(cold) ms")
        #expect(typing < budget, "typing \(typing) ms")
        #expect(rescan < budget, "rescan \(rescan) ms")
    }
}
}
