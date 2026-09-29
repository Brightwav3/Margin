/// `GraphService` over the mockup graph of `Fixtures.week5` (23 nodes, 26 edges, mockup positions).
/// Immutable: writes to fixture notes do not change it.
///
/// Node ids follow the service contract, not the mockup: hubs keep the course id, a node that is
/// one of the fixture notes gets that note's id (`bio/lecture-8`), and a node without a note is a
/// ghost (`ghost:lipids`). Labels are the mockup's.
public struct FixtureGraphService: GraphService {
    private let full: Graph
    private let courses: Set<CourseID>

    public init(world: FixtureWorld = Fixtures.week5) {
        self.full = world.serviceGraph
        self.courses = Set(world.courses.map(\.id))
    }

    public func graph(scope: GraphScope, filter: GraphFilter) async throws -> Graph {
        try GraphRules.select(full, tags: [:], scope: scope, knownCourses: courses, filter: filter)
    }

    public func ego(note: NoteID, depth: Int) async throws -> Graph {
        try GraphRules.ego(full, node: note, depth: depth)
    }

    public func layout(_ graph: Graph) -> AsyncStream<[String: LayoutPoint]> { GraphRules.layoutStream(graph) }
}

extension FixtureWorld {
    /// The mockup graph with contract ids (see `FixtureGraphService`).
    var serviceGraph: Graph {
        var ids: [String: String] = [:]
        var nodes: [GraphNode] = []
        for node in graph.nodes {
            var id = node.id
            if node.kind == .note {
                if let note = allNotes.first(where: { $0.courseID == node.courseID && Self.matches(node.label, $0.title) }) {
                    id = note.id
                } else {
                    id = GraphBuilder.ghostID(forTarget: node.label)
                }
            }
            ids[node.id] = id
            nodes.append(GraphNode(id: id, label: node.label, kind: node.kind, courseID: node.courseID, x: node.x, y: node.y))
        }
        let edges = graph.edges.compactMap { e -> GraphEdge? in
            guard let a = ids[e.source], let b = ids[e.target] else { return nil }
            return GraphEdge(source: a, target: b)
        }
        return Graph(nodes: nodes, edges: edges)
    }
}
