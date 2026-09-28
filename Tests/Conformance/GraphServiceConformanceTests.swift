import Foundation
import Testing
@testable import MarginCore

/// One suite, run against `FixtureGraphService` and `VaultGraphService` (contract §5). The two
/// graphs differ in size (mockup subset vs the whole sample vault), so the tests check the rules
/// both obey, plus the facts about the notes both graphs contain.
@Suite struct GraphServiceConformanceTests {
    let world = Fixtures.week5
    let hubs: Set<String> = ["bio", "chem", "math", "hist", "econ", "phil"]
    let lecture8 = "bio/lecture-8"

    private func all(_ h: Harness, filter: GraphFilter = .none) async throws -> Graph {
        try await h.graph.graph(scope: .all, filter: filter)
    }

    private func assertWellFormed(_ g: Graph, sourceLocation: SourceLocation = #_sourceLocation) {
        let ids = Set(g.nodes.map(\.id))
        #expect(ids.count == g.nodes.count, "unique ids", sourceLocation: sourceLocation)
        #expect(g.edges.allSatisfy { ids.contains($0.source) && ids.contains($0.target) && $0.source != $0.target },
                "edges join two nodes", sourceLocation: sourceLocation)
        #expect(Set(g.edges.map { [$0.source, $0.target].sorted() }).count == g.edges.count, "no duplicate edge",
                sourceLocation: sourceLocation)
        #expect(g.nodes.allSatisfy { (0...1000).contains($0.x) && (0...800).contains($0.y) }, "inside the canvas",
                sourceLocation: sourceLocation)
    }

    @Test(arguments: HarnessKind.allCases)
    func fullGraphHasAHubPerCourseAndTheNotesOfTheSample(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let g = try await all(h)
            assertWellFormed(g)
            #expect(Set(g.nodes.filter { $0.kind == .course }.map(\.id)) == hubs)
            for hub in g.nodes where hub.kind == .course { #expect(hub.courseID == hub.id) }
            let lecture = try #require(g.nodes.first { $0.id == lecture8 })
            #expect(lecture.kind == .note && lecture.courseID == "bio" && lecture.label == "Lecture 8 — Cell membrane")
            // The mockup's links between Bio notes exist in both graphs.
            let edges = Set(g.edges.map { Set([$0.source, $0.target]) })
            for pair in [["bio", lecture8], [lecture8, "bio/glossary"], ["bio/lecture-7", "bio/glossary"],
                         [lecture8, "bio/membrane-transport-summary"]] {
                #expect(edges.contains(Set(pair)), "\(pair)")
            }
            // Ghosts are notes without a file: "Not created yet".
            #expect(g.nodes.contains { $0.id == "ghost:lipids" && $0.kind == .note })
        }
    }

    @Test func fixtureGraphIsTheMockupGraph() async throws {
        let g = try await FixtureGraphService().graph(scope: .all, filter: .none)
        #expect(g.nodes.count == 23 && g.edges.count == 26)
        #expect(g.nodes.filter { $0.kind == .course }.count == 6)
        // Mockup positions are kept.
        #expect(g.nodes.first { $0.id == "bio" }.map { [$0.x, $0.y] } == [420, 330])
        #expect(g.nodes.first { $0.id == "bio/lecture-8" }.map { [$0.x, $0.y] } == [350, 225])
    }

    @Test(arguments: HarnessKind.allCases)
    func courseScopeKeepsOneCourse(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let g = try await h.graph.graph(scope: .course("bio"), filter: .none)
            assertWellFormed(g)
            #expect(g.nodes.contains { $0.id == "bio" && $0.kind == .course })
            #expect(g.nodes.allSatisfy { $0.courseID == "bio" })
            #expect(g.nodes.count > 3)
            #expect(!g.nodes.contains { $0.id == "chem" })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func unknownCourseScopeIsNotFound(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            do { _ = try await h.graph.graph(scope: .course("nope"), filter: .none); Issue.record("no error") }
            catch let e as MarginError { #expect(e.code == "notFound") }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func filterIsAppliedAfterTheScopeAndKeepsOrderAndPositions(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let full = try await all(h)
            let filter = GraphFilter(kinds: [.note], searchText: "LECTURE")
            let g = try await all(h, filter: filter)
            #expect(g == filter.apply(to: full))
            #expect(g.nodes.contains { $0.id == lecture8 })
            #expect(g.nodes.allSatisfy { $0.kind == .note && $0.label.lowercased().contains("lecture") })
            // The survivors are in the order of the full graph and have not moved.
            let order = full.nodes.map(\.id).filter { Set(g.nodes.map(\.id)).contains($0) }
            #expect(g.nodes.map(\.id) == order)
            for n in g.nodes { #expect(full.nodes.first { $0.id == n.id } == n) }
            // Scope and filter combine.
            let bio = try await h.graph.graph(scope: .course("bio"), filter: GraphFilter(kinds: [.course]))
            #expect(bio.nodes.map(\.id) == ["bio"])
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func positionsAreStableAcrossCalls(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let a = try await all(h), b = try await all(h)
            #expect(a == b)
            let ego = try await h.graph.ego(note: lecture8, depth: 1)
            for n in ego.nodes { #expect(a.nodes.first { $0.id == n.id } == n) }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func egoIsTheNeighbourhood(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let full = try await all(h)
            let zero = try await h.graph.ego(note: lecture8, depth: 0)
            #expect(zero.nodes.map(\.id) == [lecture8] && zero.edges.isEmpty)

            let one = try await h.graph.ego(note: lecture8, depth: 1)
            let neighbours = Set(full.edges.flatMap { $0.source == lecture8 ? [$0.target] : $0.target == lecture8 ? [$0.source] : [] })
            #expect(Set(one.nodes.map(\.id)) == neighbours.union([lecture8]))
            #expect(one.edges.count >= neighbours.count)
            let two = try await h.graph.ego(note: lecture8, depth: 2)
            #expect(Set(one.nodes.map(\.id)).isSubset(of: Set(two.nodes.map(\.id))))
            #expect(two.nodes.count > one.nodes.count)
            assertWellFormed(two)
            #expect(two == EgoGraph(of: lecture8, depth: 2, in: full)?.graph)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func egoErrors(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            do { _ = try await h.graph.ego(note: "bio/nope", depth: 1); Issue.record("no error") }
            catch let e as MarginError { #expect(e.code == "notFound") }
            do { _ = try await h.graph.ego(note: lecture8, depth: -1); Issue.record("no error") }
            catch let e as MarginError { #expect(e.code == "invalid") }
            // A course hub is a node too.
            let hub = try await h.graph.ego(note: "bio", depth: 1)
            #expect(hub.nodes.contains { $0.id == "bio" } && hub.nodes.contains { $0.id == lecture8 })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func layoutStreamSettlesInsideTheCanvasAndIsDeterministic(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let g = try await all(h)
            var runs: [[[String: LayoutPoint]]] = []
            for _ in 0..<2 {
                var snapshots: [[String: LayoutPoint]] = []
                for await s in h.graph.layout(g) { snapshots.append(s) }
                runs.append(snapshots)
            }
            let last = try #require(runs[0].last)
            #expect(Set(last.keys) == Set(g.nodes.map(\.id)))
            #expect(last.values.allSatisfy { (0...1000).contains($0.x) && (0...800).contains($0.y) })
            #expect(runs[0].allSatisfy { Set($0.keys) == Set(last.keys) })
            #expect(runs[0].last == runs[1].last)
            // The settled layout separates the nodes.
            let pts = Array(last.values)
            let distinct = Set(pts.map { "\(($0.x * 10).rounded())/\(($0.y * 10).rounded())" })
            #expect(distinct.count == pts.count)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func layoutOfEmptyAndSingleNodeGraphs(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            var empty: [[String: LayoutPoint]] = []
            for await s in h.graph.layout(Graph()) { empty.append(s) }
            #expect(empty.last == [:])

            let one = Graph(nodes: [GraphNode(id: "a", label: "A", kind: .note, x: 3, y: 4)])
            var last: [String: LayoutPoint]?
            for await s in h.graph.layout(one) { last = s }
            #expect(last == ["a": LayoutPoint(x: 500, y: 400)])
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func stoppingTheStreamEarlyIsSafe(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let g = try await all(h)
            for await _ in h.graph.layout(g) { break }
            var count = 0
            for await _ in h.graph.layout(g) { count += 1 }
            #expect(count >= 1)
        }
    }

    @Test func vaultGraphFollowsEditsMadeBehindItsBack() async throws {
        try await withHarness(.vault) { h in
            let before = try await all(h)
            try await h.editNote("bio/lecture-7", "# Lecture 7 — Organelles\n\nSee [[Glossary]] and [[Brand new idea]].\n")
            var after = before
            for _ in 0..<200 where after == before || !after.nodes.contains(where: { $0.id == "ghost:brand new idea" }) {
                try await Task.sleep(nanoseconds: 50_000_000)
                after = try await all(h)
            }
            #expect(after.nodes.contains { $0.id == "ghost:brand new idea" })
            #expect(after.edges.contains { Set([$0.source, $0.target]) == ["bio/lecture-7", "ghost:brand new idea"] })
            // Nodes that were there keep their names; the graph stays well formed.
            assertWellFormed(after)
        }
    }
}
