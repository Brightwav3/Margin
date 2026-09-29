import Foundation

/// The observable rules of `GraphService` shared by the fixture and vault implementations
/// (contract §5): scope and filter, ego, layout and fitting into the canvas.
enum GraphRules {
    /// The design's canvas.
    static let canvas = LayoutPoint(x: 1000, y: 800)
    static let margin = 40.0

    /// `scope` first (unknown course: `.notFound`), then `filter`.
    static func select(_ full: Graph, tags: [String: Set<String>], scope: GraphScope,
                       knownCourses: Set<CourseID>, filter: GraphFilter) throws -> Graph {
        var graph = full
        if case .course(let id) = scope {
            guard knownCourses.contains(id) else { throw MarginError.notFound("No course \(id)") }
            graph = GraphFilter(courseIDs: [id]).apply(to: graph)
        }
        return filter.apply(to: graph, tagsByNode: tags)
    }

    /// The neighbourhood of `node` in `full` (unknown node: `.notFound`, negative depth: `.invalid`).
    static func ego(_ full: Graph, node: String, depth: Int) throws -> Graph {
        guard depth >= 0 else { throw MarginError.invalid("Depth must not be negative (\(depth))") }
        guard let ego = EgoGraph(of: node, depth: depth, in: full) else {
            throw MarginError.notFound("No graph node \(node)")
        }
        return ego.graph
    }

    /// `graph` with a settled, fitted layout (the last snapshot of `layoutStream`).
    static func placed(_ graph: Graph) -> Graph {
        var layout = ForceLayout(graph: graph, config: .adaptive(nodeCount: graph.nodes.count))
        layout.run()
        let positions = fit(layout.positions)
        var result = graph
        for i in result.nodes.indices {
            if let p = positions[result.nodes[i].id] { result.nodes[i].x = p.x; result.nodes[i].y = p.y }
        }
        return result
    }

    static func layoutStream(_ graph: Graph) -> AsyncStream<[String: LayoutPoint]> {
        let layout = ForceLayout(graph: graph, config: .adaptive(nodeCount: graph.nodes.count))
        let source = layout.positionStream(every: 5)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await positions in source { continuation.yield(fit(positions)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Scales and shifts positions uniformly so they fill the canvas inside `margin`, centred.
    static func fit(_ positions: [String: LayoutPoint]) -> [String: LayoutPoint] {
        guard let first = positions.values.first else { return positions }
        var (minX, maxX, minY, maxY) = (first.x, first.x, first.y, first.y)
        for p in positions.values { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let w = maxX - minX, h = maxY - minY
        let availableW = canvas.x - 2 * margin, availableH = canvas.y - 2 * margin
        var scale = 1.0
        if w > 1e-9 || h > 1e-9 {
            scale = min(w > 1e-9 ? availableW / w : .infinity, h > 1e-9 ? availableH / h : .infinity)
        }
        let dx = (canvas.x - scale * (minX + maxX)) / 2
        let dy = (canvas.y - scale * (minY + maxY)) / 2
        return positions.mapValues {
            LayoutPoint(x: min(max($0.x * scale + dx, 0), canvas.x), y: min(max($0.y * scale + dy, 0), canvas.y))
        }
    }
}

/// Remembers the last layout of the vault graph so that filtering or asking again does not lay
/// out again and nodes keep their places until the vault's graph changes.
actor GraphLayoutCache {
    private var key: Graph?
    private var placed: Graph?

    /// `graph` with positions; recomputed only when nodes or edges differ from the last call.
    func place(_ graph: Graph) -> Graph {
        if let key, key == graph, let placed { return placed }
        let result = GraphRules.placed(graph)
        key = graph; placed = result
        return result
    }
}
