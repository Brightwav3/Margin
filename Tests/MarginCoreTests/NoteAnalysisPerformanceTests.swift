import Foundation
import Testing
@testable import MarginCore

/// M6-09: analysis queries stay under 30 ms on a 1000-note vault.
extension PerfSuites {
@Suite struct NoteAnalysisPerformanceTests {
    #if DEBUG
    static let slack = 5.0   // debug builds in a Docker container are far slower than release
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

    /// 1000 notes; every note links to 4 others and to a hub, so the hub has 1000 backlinks.
    private func vault(count: Int) -> [(path: String, content: String)] {
        var rng = SplitMix64(state: 7)
        let words = ["cell", "membrane", "protein", "energy", "atom", "bond", "the", "of", "and", "reaction"]
        var out: [(path: String, content: String)] = []
        for i in 0..<count {
            var text = "---\nid: n-\(i)\ntype: lecture\ndate: 2026-09-\(10 + i % 18)\ntags: [t\(i % 10), exam]\nclass: \"[[Course \(i % 8)]]\"\n---\n# Note \(i)\n\n"
            for section in 0..<5 {
                text += "## Section \(section)\n\n"
                text += (0..<80).map { _ in words[rng.below(words.count)] }.joined(separator: " ")
                if section < 4 { text += " see [[Note \(rng.below(count))]]" }
                if section == 2 { text += " and [[Hub]] or [[not written \(rng.below(40))]]" }
                text += "\n\n"
            }
            text += "- [ ] Task A \(i)\n- [x] Task B \(i)\n"
            out.append(("fall-2026/course\(i % 8)/Note \(i).md", text))
        }
        out.append(("fall-2026/course0/Hub.md", "---\nid: hub\n---\n# Hub\n\nThe hub.\n"))
        return out
    }

    @Test func queriesOnAThousandNotesStayUnder30Ms() async throws {
        let index = NoteIndex(clock: FixedClock())
        await index.build(entries: vault(count: 1000))
        #expect(await index.count == 1001)
        let engine = NoteAnalysisEngine(index: { index }, isNote: { _ in true })

        // Note 0 (typical), note 500 and the hub (1000 backlinks: the worst case for backlinks/stats).
        let ids = ["n-0", "n-500", "n-999", "hub"]
        // Every (query, note) pair is timed `perfRuns` times after a warm-up round; the budget is judged
        // on the median of those runs, and per query on the slowest note (the hub is the worst case).
        var samples: [String: [Double]] = [:]
        func time(_ name: String, _ id: String, _ body: () async throws -> Void) async throws {
            let t = ContinuousClock.now
            try await body()
            samples["\(name)/\(id)", default: []].append(perfMs(ContinuousClock.now - t))
        }
        for round in 0...perfRuns {
            for id in ids {
                try await time("outline", id) { _ = try await engine.outline(id: id) }
                try await time("backlinks", id) { _ = try await engine.backlinks(id: id) }
                try await time("outgoing", id) { _ = try await engine.outgoing(id: id) }
                try await time("stats", id) { _ = try await engine.stats(id: id, text: nil) }
                try await time("properties", id) { _ = try await engine.properties(id: id) }
            }
            if round == 0 { samples = [:] }   // warm-up round is discarded
        }
        var worst: [String: Double] = [:]
        for (key, values) in samples {
            let name = String(key.prefix { $0 != "/" })
            worst[name] = max(worst[name] ?? 0, perfMedian(values))
        }
        let hub = try await engine.backlinks(id: "hub")
        #expect(hub.count == 1000)
        let outgoing = try await engine.outgoing(id: "n-0")
        #expect(outgoing.contains { $0.state == .notCreated })

        let report = worst.keys.sorted().map { "\($0) \(String(format: "%.1f", worst[$0]!)) ms" }.joined(separator: ", ")
        print("NoteAnalysis perf on 1001 notes (slowest note, median of \(perfRuns) runs, slack x\(Self.slack)): \(report)")
        for (name, ms) in worst { #expect(ms < 30 * Self.slack, "\(name) median took \(ms) ms (budget 30 ms x \(Self.slack))") }
    }
}
}
