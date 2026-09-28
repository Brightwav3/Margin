@testable import MarginCore

/// Seeded preferential-attachment graph (Barabasi-Albert style, `m` edges per new node).
func preferentialAttachmentGraph(nodes n: Int, edgesPerNode m: Int = 2, seed: UInt64) -> Graph {
    var rng = LayoutRNG(seed: seed)
    var graph = Graph()
    var endpoints: [Int] = []
    for i in 0..<n {
        graph.nodes.append(GraphNode(id: "n\(i)", label: "Node \(i)", kind: .note, courseID: "c\(i % 5)", x: 0, y: 0))
        if i > 0 {
            var targets = Set<Int>()
            let want = min(m, i)
            while targets.count < want {
                let t = endpoints.isEmpty ? 0 : endpoints[Int(rng.next() % UInt64(endpoints.count))]
                targets.insert(t)
            }
            for t in targets.sorted() {
                graph.edges.append(GraphEdge(source: "n\(i)", target: "n\(t)"))
                endpoints.append(i); endpoints.append(t)
            }
        }
    }
    return graph
}
