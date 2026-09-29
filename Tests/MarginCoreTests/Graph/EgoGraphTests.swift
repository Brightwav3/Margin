import Testing
@testable import MarginCore

/// M9-08.B: `EgoGraph` on the fixture graph (ids of the mockup: `b1` is "Lecture 8 — Cell membrane").
@Suite struct EgoGraphTests {
    let graph = Fixtures.week5.graph

    private func ids(_ g: Graph) -> Set<String> { Set(g.nodes.map(\.id)) }

    @Test func depthZeroKeepsOnlyTheCentre() throws {
        let ego = try #require(EgoGraph(of: "b1", depth: 0, in: graph))
        #expect(ids(ego.graph) == ["b1"] && ego.graph.edges.isEmpty)
        #expect(ego.distance == ["b1": 0])
    }

    @Test func depthOneIsTheDirectNeighboursWithTheEdgesBetweenThem() throws {
        let ego = try #require(EgoGraph(of: "b1", depth: 1, in: graph))
        // Edges of b1: bio-b1, b1-b3, b1-c3, b1-b4.
        #expect(ids(ego.graph) == ["b1", "bio", "b3", "c3", "b4"])
        // Induced: also bio-b3, bio-b4, b3-b4 (both ends kept), but not chem-c3.
        #expect(Set(ego.graph.edges.map(\.id)) == ["bio--b1", "bio--b3", "bio--b4", "b1--b3", "b1--c3", "b3--b4", "b1--b4"])
        #expect(ego.nodes(atDistance: 1).count == 4)
        #expect(ego.distance["b1"] == 0 && ego.distance["c3"] == 1)
    }

    @Test func depthTwoReachesAcrossCourses() throws {
        let ego = try #require(EgoGraph(of: "b1", depth: 2, in: graph))
        // Two hops: b2 (via bio), chem (via c3).
        #expect(ids(ego.graph) == ["b1", "bio", "b3", "c3", "b4", "b2", "chem"])
        #expect(ego.distance["chem"] == 2 && ego.distance["b2"] == 2)
        #expect(ego.graph.edges.contains(GraphEdge(source: "chem", target: "c3")))
    }

    @Test func distanceIsTheShortestPathAndDirectionIsIgnored() throws {
        // p1 -> m1 is stored as p1 (source) m1 (target); from m1 the walk goes backwards along it.
        let ego = try #require(EgoGraph(of: "m1", depth: 3, in: graph))
        #expect(ego.distance["p1"] == 1)
        #expect(ego.distance["phil"] == 2)
        #expect(ego.distance["math"] == 1)
        #expect(ego.distance["e1"] == 3)   // m1 - math - m3 - e1
    }

    @Test func largeDepthGivesTheConnectedComponent() throws {
        // The mockup graph has two components: Bio + Chem (9 nodes) and the other four courses (14).
        let bio = try #require(EgoGraph(of: "bio", depth: 99, in: graph))
        #expect(bio.graph.nodes.count == 9 && bio.graph.edges.count == 12)
        #expect(bio.graph.nodes == graph.nodes.filter { bio.distance[$0.id] != nil })   // source order kept
        let econ = try #require(EgoGraph(of: "econ", depth: 99, in: graph))
        #expect(econ.graph.nodes.count == 14 && econ.graph.edges.count == 14)
        #expect(ids(bio.graph).isDisjoint(with: ids(econ.graph)))
    }

    @Test func negativeDepthActsAsZero() throws {
        let ego = try #require(EgoGraph(of: "b1", depth: -3, in: graph))
        #expect(ego.depth == 0 && ids(ego.graph) == ["b1"])
    }

    @Test func unknownCentreIsNil() {
        #expect(EgoGraph(of: "nope", depth: 1, in: graph) == nil)
        #expect(EgoGraph(of: "b1", depth: 1, in: Graph()) == nil)
    }

    @Test func isolatedNodeHasOnlyItself() throws {
        let g = Graph(nodes: [GraphNode(id: "a", label: "A", kind: .note, x: 0, y: 0),
                              GraphNode(id: "b", label: "B", kind: .note, x: 0, y: 0)], edges: [])
        let ego = try #require(EgoGraph(of: "a", depth: 5, in: g))
        #expect(ids(ego.graph) == ["a"])
    }

    @Test func positionsAreKept() throws {
        let ego = try #require(EgoGraph(of: "b1", depth: 1, in: graph))
        let b1 = try #require(ego.graph.nodes.first { $0.id == "b1" })
        #expect(b1.x == 350 && b1.y == 225)
    }
}
