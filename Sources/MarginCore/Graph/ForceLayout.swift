import Foundation

/// Why `ForceLayout.run` stopped.
public enum LayoutStopReason: String, Codable, Sendable, Hashable {
    /// Kinetic energy per node fell to the requested threshold.
    case energyThreshold
    /// The cooling schedule reached its minimum (`alpha < alphaMin`); the layout is at rest.
    case cooled
    /// The iteration budget was used up.
    case maxIterations
}

/// Result of `ForceLayout.run`.
public struct LayoutRunResult: Sendable, Hashable {
    public var iterations: Int
    public var energy: Double
    public var reason: LayoutStopReason
}

/// Tunable parameters of `ForceLayout`. Units are canvas units (the design's 1000x800 canvas).
public struct ForceLayoutConfig: Sendable, Hashable {
    /// Seed of the deterministic RNG (initial positions and coincident-node jiggle).
    public var seed: UInt64 = 1
    /// Centre of the layout (gravity target and initial cloud centre).
    public var center = LayoutPoint(x: 500, y: 400)
    /// Repulsion strength between every pair of nodes (inverse-square falloff).
    public var repulsion: Double = 30
    /// Nodes closer than this are treated as being this far apart (bounds the repulsion).
    public var minDistance: Double = 1
    /// Rest length of an edge spring.
    public var linkDistance: Double = 30
    /// Spring stiffness multiplier (per-edge strength is divided by the smaller endpoint degree).
    public var linkStrength: Double = 1
    /// Pull towards `center`, proportional to the offset.
    public var gravity: Double = 0.05
    /// Fraction of velocity lost every step (0...1).
    public var velocityDecay: Double = 0.6
    /// Barnes–Hut opening angle at full alpha (coarse, cheap). Larger is coarser.
    public var thetaCoarse: Double = 0.9
    /// Opening angle when nearly cooled (fine). Equal to `thetaCoarse` disables adaptation.
    public var thetaFine: Double = 0.9
    /// Alpha starts at 1 and decays towards 0; forces are scaled by alpha.
    public var alphaDecay: Double = 1 - pow(0.001, 1.0 / 300.0)
    /// The layout counts as cooled below this alpha.
    public var alphaMin: Double = 0.001
    /// Largest displacement of one node in one step.
    public var maxStep: Double = 60
    /// Radius scale of the initial random disc (radius = scale * sqrt(n)).
    public var initialRadiusScale: Double = 12

    public init() {}

    /// Preset that trades precision for speed as graphs grow: a coarser opening angle early in
    /// the cooling schedule and a shorter schedule. Identical to the defaults up to 500 nodes;
    /// fully coarsened at 5000 and above.
    public static func adaptive(nodeCount n: Int, seed: UInt64 = 1) -> ForceLayoutConfig {
        var c = ForceLayoutConfig()
        c.seed = seed
        guard n > 500 else { return c }
        let t = min(1, log(Double(n) / 500) / log(10))
        c.thetaCoarse = 0.9 + 0.5 * t
        c.thetaFine = 0.9
        c.alphaDecay = 1 - pow(c.alphaMin, 1.0 / (300 - 150 * t))
        return c
    }
}

/// Deterministic Barnes–Hut force-directed layout.
///
/// Forces: inverse-square repulsion (approximated with a quadtree), springs along edges, gravity
/// towards the centre and velocity damping, all scaled by a cooling `alpha`. Pinned nodes never
/// move. The same graph, seed and configuration give bitwise identical positions. A value type:
/// copying it forks the simulation.
public struct ForceLayout: Sendable {
    public typealias NodeID = String

    public private(set) var config: ForceLayoutConfig
    /// Node ids in input order; indices below refer to this order.
    public let ids: [NodeID]
    public private(set) var alpha: Double = 1
    public private(set) var iterations = 0

    private var xs: [Double]
    private var ys: [Double]
    private var vx: [Double]
    private var vy: [Double]
    private var pinned: [Bool]
    private let indexByID: [NodeID: Int]
    private let edgeSource: [Int]
    private let edgeTarget: [Int]
    private let edgeStrength: [Double]
    private let edgeBias: [Double]
    private var tree = QuadTree()
    private var rng: LayoutRNG
    private var stack = [Int32](repeating: 0, count: 4 * QuadTree.maxDepth + 8)

    /// Creates a layout for a graph. Existing node coordinates are ignored unless listed in
    /// `initialPositions`; the rest start on a seeded random disc around the centre.
    /// Edges that reference unknown nodes, self loops and duplicates are ignored.
    public init(graph: Graph, config: ForceLayoutConfig = ForceLayoutConfig(),
                initialPositions: [NodeID: LayoutPoint] = [:], pinned pinnedIDs: Set<NodeID> = []) {
        self.init(ids: graph.nodes.map(\.id), edges: graph.edges.map { ($0.source, $0.target) },
                  config: config, initialPositions: initialPositions, pinned: pinnedIDs)
    }

    public init(ids nodeIDs: [NodeID], edges: [(NodeID, NodeID)],
                config: ForceLayoutConfig = ForceLayoutConfig(),
                initialPositions: [NodeID: LayoutPoint] = [:], pinned pinnedIDs: Set<NodeID> = []) {
        // Drop duplicate ids, keeping first occurrences.
        var index: [NodeID: Int] = [:]
        var unique: [NodeID] = []
        unique.reserveCapacity(nodeIDs.count)
        for id in nodeIDs where index[id] == nil {
            index[id] = unique.count; unique.append(id)
        }
        let n = unique.count
        var rng = LayoutRNG(seed: config.seed)
        let radius = config.initialRadiusScale * Double(n).squareRoot()
        var xs = [Double](repeating: 0, count: n), ys = xs
        for i in 0..<n {
            if let p = initialPositions[unique[i]] {
                xs[i] = p.x; ys[i] = p.y
            } else {
                // Draw both numbers always, so positions do not depend on which nodes are given.
                let r = radius * rng.nextUnit().squareRoot()
                let a = 2 * Double.pi * rng.nextUnit()
                xs[i] = config.center.x + r * cos(a); ys[i] = config.center.y + r * sin(a)
            }
        }
        // Normalised, deduplicated edges (order of first occurrence).
        var seen = Set<UInt64>()
        var src: [Int] = [], dst: [Int] = []
        var degree = [Int](repeating: 0, count: n)
        for (a, b) in edges {
            guard let s = index[a], let t = index[b], s != t else { continue }
            let key = UInt64(min(s, t)) << 32 | UInt64(max(s, t))
            guard seen.insert(key).inserted else { continue }
            src.append(s); dst.append(t); degree[s] += 1; degree[t] += 1
        }
        self.config = config
        self.ids = unique
        self.indexByID = index
        self.xs = xs; self.ys = ys
        self.vx = [Double](repeating: 0, count: n); self.vy = vx
        self.pinned = unique.map { pinnedIDs.contains($0) }
        self.edgeSource = src; self.edgeTarget = dst
        self.edgeStrength = zip(src, dst).map { 1.0 / Double(min(degree[$0], degree[$1])) }
        self.edgeBias = zip(src, dst).map { Double(degree[$0]) / Double(degree[$0] + degree[$1]) }
        self.rng = rng
    }

    // MARK: State

    public var nodeCount: Int { ids.count }

    /// Current positions by node id.
    public var positions: [NodeID: LayoutPoint] {
        var result: [NodeID: LayoutPoint] = [:]
        result.reserveCapacity(ids.count)
        for i in 0..<ids.count { result[ids[i]] = LayoutPoint(x: xs[i], y: ys[i]) }
        return result
    }

    public func position(of id: NodeID) -> LayoutPoint? {
        indexByID[id].map { LayoutPoint(x: xs[$0], y: ys[$0]) }
    }

    /// Mean kinetic energy per node (`sum |v|^2 / n`).
    public var energy: Double {
        guard !ids.isEmpty else { return 0 }
        var sum = 0.0
        for i in 0..<ids.count { sum += vx[i] * vx[i] + vy[i] * vy[i] }
        return sum / Double(ids.count)
    }

    public var isCooled: Bool { alpha < config.alphaMin }

    /// Pins a node, optionally moving it. A pinned node keeps its position during `step()`.
    public mutating func pin(_ id: NodeID, at point: LayoutPoint? = nil) {
        guard let i = indexByID[id] else { return }
        pinned[i] = true
        if let point { xs[i] = point.x; ys[i] = point.y }
        vx[i] = 0; vy[i] = 0
    }

    public mutating func unpin(_ id: NodeID) {
        if let i = indexByID[id] { pinned[i] = false }
    }

    public func isPinned(_ id: NodeID) -> Bool { indexByID[id].map { pinned[$0] } ?? false }

    /// Restarts the cooling schedule (for example after dragging a node), keeping positions.
    public mutating func reheat(alpha: Double = 1) { self.alpha = max(0, min(1, alpha)) }

    // MARK: Simulation

    /// Advances the simulation by one step. Does nothing once cooled.
    public mutating func step() {
        let n = ids.count
        guard n > 0, !isCooled else { alpha = 0; return }
        iterations += 1
        applyRepulsion()
        applySprings()
        for i in 0..<n where !pinned[i] {
            vx[i] += (config.center.x - xs[i]) * config.gravity * alpha
            vy[i] += (config.center.y - ys[i]) * config.gravity * alpha
        }
        let keep = 1 - config.velocityDecay
        let limit = config.maxStep
        for i in 0..<n {
            if pinned[i] { vx[i] = 0; vy[i] = 0; continue }
            vx[i] = max(-limit, min(limit, vx[i] * keep))
            vy[i] = max(-limit, min(limit, vy[i] * keep))
            xs[i] += vx[i]; ys[i] += vy[i]
        }
        alpha -= alpha * config.alphaDecay
    }

    /// Steps until the energy drops to `energyThreshold`, the layout is cooled, or
    /// `maxIterations` steps have been taken.
    @discardableResult
    public mutating func run(until energyThreshold: Double = 0.01, maxIterations: Int = 1000) -> LayoutRunResult {
        var taken = 0
        while true {
            if isCooled { return LayoutRunResult(iterations: taken, energy: energy, reason: .cooled) }
            if taken >= maxIterations {
                return LayoutRunResult(iterations: taken, energy: energy, reason: .maxIterations)
            }
            step(); taken += 1
            let e = energy
            if e <= energyThreshold { return LayoutRunResult(iterations: taken, energy: e, reason: .energyThreshold) }
        }
    }

    /// Stream of position snapshots for animation. Runs the simulation on a copy in a background
    /// task, yielding every `every` steps and once more at the end; the stream then finishes.
    public func positionStream(every: Int = 1, energyThreshold: Double = 0.01,
                               maxIterations: Int = 1000) -> AsyncStream<[NodeID: LayoutPoint]> {
        let start = self
        let interval = max(1, every)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached {
                var copy = start
                var taken = 0
                while !Task.isCancelled {
                    if copy.isCooled || taken >= maxIterations { break }
                    copy.step(); taken += 1
                    if copy.energy <= energyThreshold { break }
                    if taken % interval == 0 { continuation.yield(copy.positions) }
                    await Task.yield()
                }
                continuation.yield(copy.positions)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Returns `graph` with node coordinates replaced by the current positions. If `fitting` is
    /// set, positions are scaled and shifted uniformly to fit inside it (with `margin`).
    public func applying(to graph: Graph, fitting size: LayoutPoint? = nil, margin: Double = 40) -> Graph {
        var result = graph
        var scale = 1.0, dx = 0.0, dy = 0.0
        if let size, !ids.isEmpty {
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            let w = max(maxX - minX, 1e-9), h = max(maxY - minY, 1e-9)
            scale = min((size.x - 2 * margin) / w, (size.y - 2 * margin) / h)
            dx = (size.x - scale * (minX + maxX)) / 2
            dy = (size.y - scale * (minY + maxY)) / 2
        }
        for k in result.nodes.indices {
            guard let i = indexByID[result.nodes[k].id] else { continue }
            result.nodes[k].x = xs[i] * scale + dx
            result.nodes[k].y = ys[i] * scale + dy
        }
        return result
    }

    // MARK: Forces

    private var currentTheta: Double {
        let t = min(1, max(0, alpha))
        return config.thetaFine + (config.thetaCoarse - config.thetaFine) * t
    }

    private mutating func applyRepulsion() {
        let n = ids.count
        tree.build(xs: xs, ys: ys)
        let theta2 = currentTheta * currentTheta
        let k = config.repulsion * alpha
        let minD2 = config.minDistance * config.minDistance
        var localRNG = rng
        let t = tree
        t.withBuffers { b in
            stack.withUnsafeMutableBufferPointer { stack in
                for i in 0..<n where !pinned[i] {
                    let px = xs[i], py = ys[i]
                    var fx = 0.0, fy = 0.0
                    stack[0] = 0
                    var top = 1
                    while top > 0 {
                        top -= 1
                        let c = Int(stack[top])
                        let m = b.mass[c]
                        if m == 0 { continue }
                        let child = b.firstChild[c]
                        if child < 0 {
                            if Int(b.body[c]) == i { continue }
                        } else {
                            let w = b.cellHalf[c] * 2
                            let ddx = b.comX[c] - px, ddy = b.comY[c] - py
                            if w * w >= theta2 * (ddx * ddx + ddy * ddy) {
                                stack[top] = child; stack[top + 1] = child + 1
                                stack[top + 2] = child + 2; stack[top + 3] = child + 3
                                top += 4
                                continue
                            }
                        }
                        var dx = px - b.comX[c], dy = py - b.comY[c]
                        if dx == 0 { dx = (localRNG.nextUnit() - 0.5) * 1e-6 }
                        if dy == 0 { dy = (localRNG.nextUnit() - 0.5) * 1e-6 }
                        var d2 = dx * dx + dy * dy
                        if d2 < minD2 { d2 = (minD2 * d2).squareRoot() }
                        let s = k * m / d2
                        fx += dx * s; fy += dy * s
                    }
                    vx[i] += fx; vy[i] += fy
                }
            }
        }
        rng = localRNG
    }

    private mutating func jiggle() -> Double { (rng.nextUnit() - 0.5) * 1e-6 }

    private mutating func applySprings() {
        for e in 0..<edgeSource.count {
            let s = edgeSource[e], t = edgeTarget[e]
            var dx = xs[t] + vx[t] - xs[s] - vx[s]
            var dy = ys[t] + vy[t] - ys[s] - vy[s]
            if dx == 0 { dx = jiggle() }
            if dy == 0 { dy = jiggle() }
            let l = (dx * dx + dy * dy).squareRoot()
            let f = (l - config.linkDistance) / l * alpha * config.linkStrength * edgeStrength[e]
            dx *= f; dy *= f
            let b = edgeBias[e]
            if !pinned[t] { vx[t] -= dx * b; vy[t] -= dy * b }
            if !pinned[s] { vx[s] += dx * (1 - b); vy[s] += dy * (1 - b) }
        }
    }
}
