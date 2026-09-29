/// `GraphService` over a vault: the graph is built from the note index on every call
/// (`GraphBuilder`), laid out once per distinct graph and filtered afterwards.
public struct VaultGraphService: GraphService {
    let backend: VaultBackend
    private let cache = GraphLayoutCache()

    init(backend: VaultBackend) { self.backend = backend }

    public func graph(scope: GraphScope, filter: GraphFilter) async throws -> Graph {
        let (full, tags, courses) = await placedGraph()
        return try GraphRules.select(full, tags: tags, scope: scope, knownCourses: courses, filter: filter)
    }

    public func ego(note: NoteID, depth: Int) async throws -> Graph {
        try GraphRules.ego(await placedGraph().graph, node: note, depth: depth)
    }

    public func layout(_ graph: Graph) -> AsyncStream<[String: LayoutPoint]> { GraphRules.layoutStream(graph) }

    private func placedGraph() async -> (graph: Graph, tags: [String: Set<String>], courses: Set<CourseID>) {
        let snapshot = await backend.graphSnapshot()
        let placed = await cache.place(snapshot.graph)
        let courses = Set(snapshot.graph.nodes.filter { $0.kind == .course }.map(\.id))
        return (placed, snapshot.tagsByNode, courses)
    }
}
