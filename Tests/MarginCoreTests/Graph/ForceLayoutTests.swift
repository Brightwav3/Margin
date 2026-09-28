import Foundation
import Testing
@testable import MarginCore

@Suite struct ForceLayoutTests {
    let graph = Fixtures.week5.graph

    private func bits(_ p: [String: LayoutPoint]) -> [String: [UInt64]] {
        p.mapValues { [$0.x.bitPattern, $0.y.bitPattern] }
    }

    @Test func rngIsDeterministicAndUniform() {
        var a = LayoutRNG(seed: 42), b = LayoutRNG(seed: 42), c = LayoutRNG(seed: 43)
        let xs = (0..<100).map { _ in a.next() }
        #expect(xs == (0..<100).map { _ in b.next() })
        #expect(xs != (0..<100).map { _ in c.next() })
        var r = LayoutRNG(seed: 7)
        let units = (0..<1000).map { _ in r.nextUnit() }
        #expect(units.allSatisfy { $0 >= 0 && $0 < 1 })
        #expect(abs(units.reduce(0, +) / 1000 - 0.5) < 0.05)
    }

    @Test func sameSeedGivesBitwiseIdenticalPositions() {
        var a = ForceLayout(graph: graph, config: cfg(seed: 9))
        var b = ForceLayout(graph: graph, config: cfg(seed: 9))
        a.run(); b.run()
        #expect(bits(a.positions) == bits(b.positions))
        #expect(a.iterations == b.iterations)
        var c = ForceLayout(graph: graph, config: cfg(seed: 10))
        c.run()
        #expect(bits(a.positions) != bits(c.positions))
    }

    @Test func positionsAreFiniteAndDistinct() {
        var layout = ForceLayout(graph: graph)
        let result = layout.run()
        #expect(result.iterations > 0)
        let p = layout.positions
        #expect(p.count == 23)
        #expect(p.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        let pts = Array(p.values)
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                #expect(hypot(pts[i].x - pts[j].x, pts[i].y - pts[j].y) > 1)
            }
        }
    }

    @Test func connectedNodesEndUpCloserThanStrangers() {
        var layout = ForceLayout(graph: graph)
        layout.run()
        let p = layout.positions
        func d(_ a: String, _ b: String) -> Double { hypot(p[a]!.x - p[b]!.x, p[a]!.y - p[b]!.y) }
        // Course hub to its own leaf note vs to a far-away course's leaf.
        #expect(d("hist", "h1") < d("hist", "p1"))
        #expect(d("chem", "c1") < d("chem", "h1"))
        // Everything stays near the centre.
        #expect(p.values.allSatisfy { hypot($0.x - 500, $0.y - 400) < 800 })
    }

    @Test func pinnedNodesDoNotMove() {
        let anchor = LayoutPoint(x: 100, y: 100)
        var layout = ForceLayout(graph: graph, pinned: ["bio"])
        layout.pin("bio", at: anchor)
        #expect(layout.isPinned("bio"))
        layout.run()
        #expect(layout.position(of: "bio") == anchor)
        layout.unpin("bio")
        #expect(!layout.isPinned("bio"))
        layout.reheat()
        layout.run(maxIterations: 20)
        #expect(layout.position(of: "bio") != anchor)
    }

    @Test func stepIsIncrementalAndStopsWhenCooled() {
        var layout = ForceLayout(graph: graph)
        let before = layout.positions
        layout.step()
        #expect(layout.iterations == 1)
        #expect(layout.positions != before)
        let result = layout.run(until: -1, maxIterations: 100_000)
        #expect(result.reason == .cooled)
        #expect(layout.isCooled)
        let frozen = layout.positions
        layout.step()
        #expect(layout.positions == frozen)
        #expect(layout.run().iterations == 0)
    }

    @Test func runHonoursMaxIterationsAndEnergyThreshold() {
        var a = ForceLayout(graph: graph)
        let r = a.run(until: -1, maxIterations: 5)
        #expect(r.reason == .maxIterations && r.iterations == 5)
        var b = ForceLayout(graph: graph)
        let r2 = b.run(until: 1e9, maxIterations: 100)
        #expect(r2.reason == .energyThreshold && r2.iterations == 1)
    }

    @Test func stepsMatchRunPositions() {
        var a = ForceLayout(graph: graph), b = ForceLayout(graph: graph)
        for _ in 0..<30 { a.step() }
        b.run(until: -1, maxIterations: 30)
        #expect(bits(a.positions) == bits(b.positions))
    }

    @Test func degenerateInputs() {
        var empty = ForceLayout(graph: Graph())
        empty.step()
        #expect(empty.run().iterations >= 0)
        #expect(empty.positions.isEmpty)
        var one = ForceLayout(ids: ["a", "a", "b"], edges: [("a", "b"), ("b", "a"), ("a", "a"), ("a", "zzz")])
        #expect(one.nodeCount == 2)
        one.run()
        #expect(one.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        // Coincident starting points separate (jiggle) instead of producing NaN.
        let same = LayoutPoint(x: 5, y: 5)
        var stacked = ForceLayout(ids: ["a", "b", "c"], edges: [], initialPositions: ["a": same, "b": same, "c": same])
        stacked.run()
        let p = stacked.positions
        #expect(p.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(p["a"] != p["b"])
    }

    @Test func barnesHutMatchesDirectSum() {
        // With theta = 0 the tree opens every cell, so one step equals the exact O(n^2) result.
        let g = preferentialAttachmentGraph(nodes: 60, seed: 3)
        var c = ForceLayoutConfig(); c.thetaCoarse = 0; c.thetaFine = 0; c.gravity = 0; c.linkStrength = 0
        var exact = ForceLayout(graph: g, config: c)
        let start = exact.positions
        exact.step()
        let ids = g.nodes.map(\.id)
        let k = c.repulsion * 1.0, keep = 1 - c.velocityDecay
        for id in ids {
            var fx = 0.0, fy = 0.0
            let p = start[id]!
            for other in ids where other != id {
                let q = start[other]!
                let dx = p.x - q.x, dy = p.y - q.y
                var d2 = dx * dx + dy * dy
                if d2 < 1 { d2 = d2.squareRoot() }
                fx += dx * k / d2; fy += dy * k / d2
            }
            let now = exact.position(of: id)!
            #expect(abs(now.x - (p.x + fx * keep)) < 1e-9)
            #expect(abs(now.y - (p.y + fy * keep)) < 1e-9)
        }
    }

    @Test func applyingWritesPositionsBackAndFits() {
        var layout = ForceLayout(graph: graph)
        layout.run()
        let plain = layout.applying(to: graph)
        #expect(plain.edges == graph.edges && plain.nodes.map(\.id) == graph.nodes.map(\.id))
        #expect(plain.nodes[0].x == layout.position(of: "bio")!.x)
        let fitted = layout.applying(to: graph, fitting: LayoutPoint(x: 1000, y: 800), margin: 40)
        #expect(fitted.nodes.allSatisfy { $0.x >= 39.999 && $0.x <= 960.001 && $0.y >= 39.999 && $0.y <= 760.001 })
    }

    @Test func streamYieldsSnapshotsAndFinishes() async {
        let layout = ForceLayout(graph: graph)
        var snapshots: [[String: LayoutPoint]] = []
        for await frame in layout.positionStream(every: 10, maxIterations: 200) { snapshots.append(frame) }
        #expect(!snapshots.isEmpty)
        #expect(snapshots.allSatisfy { $0.count == 23 })
        var direct = layout
        direct.run(until: 0.01, maxIterations: 200)
        #expect(bits(snapshots.last!) == bits(direct.positions))
    }

    @Test func fiveHundredNodesStabilizeQuickly() {
        let g = preferentialAttachmentGraph(nodes: 500, seed: 11)
        var layout = ForceLayout(graph: g, config: ForceLayoutConfig())
        let clock = ContinuousClock()
        var result = LayoutRunResult(iterations: 0, energy: 0, reason: .maxIterations)
        let elapsed = clock.measure { result = layout.run() }
        print("ForceLayout 500 nodes: \(elapsed), \(result.iterations) iterations, \(result.reason)")
        #expect(layout.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(result.reason != .maxIterations)
        #expect(elapsed < .seconds(perfBudget(release: 2, debug: 20)))
    }

    private func cfg(seed: UInt64) -> ForceLayoutConfig { var c = ForceLayoutConfig(); c.seed = seed; return c }
}

/// Budget in seconds: strict in release builds, generous in debug (slow container).
func perfBudget(release: Double, debug: Double) -> Double {
    #if DEBUG
    return debug
    #else
    return release
    #endif
}
