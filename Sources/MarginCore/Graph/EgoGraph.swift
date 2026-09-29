/// The neighbourhood of one node, up to a number of hops (M9-08.B): the "local graph" of a note.
///
/// The subgraph is induced (every edge between two kept nodes is kept), node and edge order of the
/// source graph are preserved and positions are not touched. Distances are measured over the
/// whole graph, ignoring edge direction, so a node is at its shortest distance from the centre.
public struct EgoGraph: Sendable, Hashable {
    public let center: String
    /// The requested number of hops (negative values are treated as 0).
    public let depth: Int
    public let graph: Graph
    /// Hops from the centre for every node of `graph` (the centre is 0).
    public let distance: [String: Int]

    /// The neighbourhood of `center` within `depth` hops, or `nil` when `center` is not a node of
    /// `graph`. `depth == 0` keeps only the centre.
    public init?(of center: String, depth: Int, in graph: Graph) {
        guard graph.nodes.contains(where: { $0.id == center }) else { return nil }
        let hops = max(0, depth)
        // The filter does the breadth-first walk and the induced subgraph; only the distances are
        // computed here.
        let kept = GraphFilter(focus: center, depth: hops).apply(to: graph)
        self.center = center
        self.depth = hops
        self.graph = kept
        self.distance = Self.distances(from: center, within: hops, edges: graph.edges)
    }

    /// Nodes at exactly `hops` from the centre, in graph order.
    public func nodes(atDistance hops: Int) -> [GraphNode] {
        graph.nodes.filter { distance[$0.id] == hops }
    }

    static func distances(from start: String, within depth: Int, edges: [GraphEdge]) -> [String: Int] {
        var adjacency: [String: [String]] = [:]
        for e in edges {
            adjacency[e.source, default: []].append(e.target)
            adjacency[e.target, default: []].append(e.source)
        }
        var result: [String: Int] = [start: 0]
        var frontier = [start]
        var hops = 0
        while hops < depth && !frontier.isEmpty {
            hops += 1
            var next: [String] = []
            for id in frontier {
                for n in adjacency[id] ?? [] where result[n] == nil { result[n] = hops; next.append(n) }
            }
            frontier = next
        }
        return result
    }
}
