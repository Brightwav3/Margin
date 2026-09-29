import Foundation
import Testing
@testable import MarginCore

extension PerfSuites {
@Suite struct ForceLayoutPerfTests {
    private func measure(nodes n: Int, graphSeed: UInt64 = 21, config: ForceLayoutConfig) -> (Duration, LayoutRunResult, ForceLayout) {
        let g = preferentialAttachmentGraph(nodes: n, seed: graphSeed)
        var layout = ForceLayout(graph: g, config: config)
        var result = LayoutRunResult(iterations: 0, energy: 0, reason: .maxIterations)
        let elapsed = ContinuousClock().measure { result = layout.run() }
        return (elapsed, result, layout)
    }

    private func meanEdgeLength(_ layout: ForceLayout, _ g: Graph) -> Double {
        let p = layout.positions
        let sum = g.edges.reduce(0.0) { $0 + hypot(p[$1.source]!.x - p[$1.target]!.x, p[$1.source]!.y - p[$1.target]!.y) }
        return sum / Double(g.edges.count)
    }

    @Test func fiveThousandNodesStabilizeWithinBudget() {
        let n = 5000
        var last: (LayoutRunResult, ForceLayout)?
        let times = perfSamples { () -> Double in
            let (t, r, layout) = measure(nodes: n, config: .adaptive(nodeCount: n, seed: 5))
            last = (r, layout)
            return perfMs(t) / 1000
        }
        let median = perfMedian(times)
        let (r, layout) = last!
        print("PERF adaptive \(n) nodes: median \(median) s of \(times), \(r.iterations) iterations, \(r.reason)")
        #expect(r.reason != .maxIterations)
        #expect(layout.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(median < perfBudget(release: 5, debug: 30), "median \(median) s")
    }

    @Test func fiveHundredNodesStabilizeQuickly() {
        var last: (LayoutRunResult, ForceLayout)?
        let times = perfSamples { () -> Double in
            let (t, r, layout) = measure(nodes: 500, graphSeed: 11, config: ForceLayoutConfig())
            last = (r, layout)
            return perfMs(t) / 1000
        }
        let median = perfMedian(times)
        let (result, layout) = last!
        print("ForceLayout 500 nodes: median \(median) s of \(times), \(result.iterations) iterations, \(result.reason)")
        #expect(layout.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(result.reason != .maxIterations)
        #expect(median < perfBudget(release: 2, debug: 20), "median \(median) s")
    }

    @Test func adaptiveMatchesDefaultsForSmallGraphsAndCoarsensForLarge() {
        #expect(ForceLayoutConfig.adaptive(nodeCount: 500) == ForceLayoutConfig())
        let big = ForceLayoutConfig.adaptive(nodeCount: 5000)
        #expect(big.thetaCoarse > ForceLayoutConfig().thetaCoarse)
        #expect(big.alphaDecay > ForceLayoutConfig().alphaDecay)
        #expect(ForceLayoutConfig.adaptive(nodeCount: 50_000) == ForceLayoutConfig.adaptive(nodeCount: 100_000))
    }

    @Test func adaptiveKeepsLayoutQuality() {
        let n = 2000
        let g = preferentialAttachmentGraph(nodes: n, seed: 8)
        var fine = ForceLayout(graph: g, config: ForceLayoutConfig())
        fine.run(until: -1, maxIterations: 300)
        var fast = ForceLayout(graph: g, config: .adaptive(nodeCount: n))
        fast.run(until: -1, maxIterations: 300)
        let a = meanEdgeLength(fine, g), b = meanEdgeLength(fast, g)
        print("PERF mean edge length, precise \(a) vs adaptive \(b)")
        #expect(abs(a - b) / a < 0.35)
    }

    @Test func treeArenaIsReusedAcrossSteps() {
        let g = preferentialAttachmentGraph(nodes: 300, seed: 4)
        var tree = QuadTree()
        let xs = g.nodes.indices.map { Double($0 % 17) * 3.1 }, ys = g.nodes.indices.map { Double($0 % 23) * 2.7 }
        tree.build(xs: xs, ys: ys)
        let capacity = tree.mass.count, cells = tree.cellCount
        tree.build(xs: xs, ys: ys)
        #expect(tree.mass.count == capacity && tree.cellCount == cells)
        #expect(tree.mass[0] == Double(xs.count))
        // Mass of the root's children adds up to the total.
        let first = Int(tree.firstChild[0])
        #expect((first..<first + 4).reduce(0.0) { $0 + tree.mass[$1] } == Double(xs.count))
    }

    @Test func coincidentPointsDoNotBlowUpTree() {
        var tree = QuadTree()
        tree.build(xs: [1, 1, 1, 1, 2], ys: [1, 1, 1, 1, 2])
        #expect(tree.mass[0] == 5)
        #expect(tree.cellCount < 1000)
    }
}
}
