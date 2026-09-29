/// The knowledge graph (M9): nodes, links and their layout.
///
/// Node ids: a course hub has the course id; a note has its note id; a link target that has no
/// note yet ("Not created yet") has `ghost:<normalised target>`. So an id from `NoteRepository`
/// can be used directly with `ego(note:depth:)`, and the same note has the same node id in every
/// implementation.
///
/// Implementations: `FixtureGraphService` (the mockup graph of `Fixtures.week5`, 23 nodes) and
/// `VaultGraphService` (built from the note index by `GraphBuilder`). The two graphs differ in
/// size (the mockup draws a subset of the notes and six notes that do not exist), so the
/// conformance suite `Tests/Conformance/GraphServiceConformanceTests.swift` checks the rules both
/// obey, not the counts:
///
/// - **Nodes:** one hub per course of the vault; notes with their course; `courseID` set on every
///   node that has a course. Ids are unique, every edge joins two nodes of the graph, no edge joins
///   a node to itself and no pair is joined twice.
/// - **Edges:** an undirected link per pair of notes that link to each other, a hub -> note edge
///   per note of a course (for notes shown) and note -> ghost edges.
/// - **Positions:** every node of `graph`/`ego` has a position inside the canvas (0...1000,
///   0...800). Positions of one node do not change between calls while the vault does not change,
///   whichever `filter` or `scope` is asked for, so a filter does not make nodes jump.
/// - **Filter:** applied as `GraphFilter.apply` after the scope; the node and edge order of the
///   unfiltered graph is kept. `filter.focus`/`filter.depth` work like `ego`, on the filtered graph.
/// - **Errors:** an unknown course in `scope` or an unknown node in `ego` is `.notFound`; a
///   negative `depth` is `.invalid`.
public protocol GraphService: Sendable {
    /// The graph of `scope`, reduced by `filter`.
    func graph(scope: GraphScope, filter: GraphFilter) async throws -> Graph

    /// The neighbourhood of a node (a note id, a course id or a ghost id) up to `depth` hops,
    /// `depth == 0` being the node alone. Edges are followed in both directions; the result is the
    /// induced subgraph, positions as in `graph(scope: .all, filter: .none)`.
    func ego(note: NoteID, depth: Int) async throws -> Graph

    /// Runs the force layout on `graph` (its coordinates are ignored) and streams snapshots of the
    /// positions for animation, the last one being the settled layout; then the stream finishes.
    /// Deterministic: the same graph gives the same snapshots. Every snapshot has an entry for
    /// every node and is fitted into the canvas. Ending iteration stops the computation.
    func layout(_ graph: Graph) -> AsyncStream<[String: LayoutPoint]>
}
