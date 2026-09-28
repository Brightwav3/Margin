import Foundation
import Testing
@testable import MarginCore

@Suite struct GraphFilterTests {
    let graph = Fixtures.week5.graph
    let tags: [String: Set<String>] = [
        "b1": ["exam", "Membrane"], "b3": ["membrane"], "c3": ["exam"], "m1": ["exam", "math"],
    ]

    private func ids(_ g: Graph) -> Set<String> { Set(g.nodes.map(\.id)) }

    @Test func identityKeepsEverything() {
        #expect(GraphFilter.none.isIdentity)
        #expect(GraphFilter().apply(to: graph) == graph)
        #expect(graph.nodes.count == 23 && graph.edges.count == 26)
    }

    @Test func courseFilterKeepsHubAndNotesAndInducedEdges() {
        let g = GraphFilter(courseIDs: ["bio"]).apply(to: graph)
        #expect(ids(g) == ["bio", "b1", "b2", "b3", "b4"])
        #expect(g.edges.count == 8)
        #expect(g.edges.allSatisfy { ids(g).contains($0.source) && ids(g).contains($0.target) })
        let two = GraphFilter(courseIDs: ["bio", "chem"]).apply(to: graph)
        #expect(ids(two).count == 9)
        #expect(two.edges.contains(GraphEdge(source: "b1", target: "c3")))
    }

    @Test func kindFilter() {
        let hubs = GraphFilter(kinds: [.course]).apply(to: graph)
        #expect(hubs.nodes.count == 6 && hubs.edges.isEmpty)
        let notes = GraphFilter(kinds: [.note]).apply(to: graph)
        #expect(notes.nodes.count == 17 && notes.nodes.allSatisfy { $0.kind == .note })
    }

    @Test func tagFilterAnyAllAndHubsUntouched() {
        let any = GraphFilter(tags: ["EXAM"]).apply(to: graph, tagsByNode: tags)
        #expect(ids(any) == ["b1", "c3", "m1", "bio", "chem", "math", "hist", "econ", "phil"])
        let all = GraphFilter(tags: ["exam", "membrane"], tagMatch: .all).apply(to: graph, tagsByNode: tags)
        #expect(ids(all).filter { $0.count == 2 && $0.hasPrefix("b") } == ["b1"])
        let notesOnly = GraphFilter(tags: ["membrane"], kinds: [.note]).apply(to: graph, tagsByNode: tags)
        #expect(ids(notesOnly) == ["b1", "b3"])
        #expect(notesOnly.edges == [GraphEdge(source: "b1", target: "b3")])
        // Without a tag map nothing matches.
        #expect(GraphFilter(tags: ["exam"], kinds: [.note]).apply(to: graph).nodes.isEmpty)
    }

    @Test func orphansOffDropsUnconnectedNodes() {
        let g = GraphFilter(kinds: [.note], showOrphans: false).apply(to: graph)
        let connected = Set(g.edges.flatMap { [$0.source, $0.target] })
        #expect(ids(g) == connected)
        #expect(ids(g).isSuperset(of: ["b1", "b2", "b3", "b4"]))
        #expect(!ids(g).contains("c1") && !ids(g).contains("h1"))
        #expect(GraphFilter(showOrphans: false).apply(to: graph) == graph)
        let on = GraphFilter(kinds: [.note], showOrphans: true).apply(to: graph)
        #expect(on.nodes.count == 17)
    }

    @Test func searchTextIsCaseAndDiacriticInsensitive() {
        #expect(ids(GraphFilter(searchText: "MEMBRANE").apply(to: graph)) == ["b1", "b3"])
        #expect(ids(GraphFilter(searchText: "  lipids ").apply(to: graph)) == ["c3"])
        #expect(ids(GraphFilter(searchText: "is-lm").apply(to: graph)).isEmpty)  // en dash differs
        #expect(ids(GraphFilter(searchText: "is–lm").apply(to: graph)) == ["e1"])
        #expect(GraphFilter(searchText: "   ").apply(to: graph) == graph)
        let accents = Graph(nodes: [GraphNode(id: "a", label: "Přednáška Čtvrtá", kind: .note, courseID: "x", x: 0, y: 0)])
        #expect(GraphFilter(searchText: "prednaska ctvrta").apply(to: accents).nodes.count == 1)
    }

    @Test func depthLimitsNeighbourhoodOfFocus() {
        let d0 = GraphFilter(focus: "bio", depth: 0).apply(to: graph)
        #expect(ids(d0) == ["bio"])
        let d1 = GraphFilter(focus: "bio", depth: 1).apply(to: graph)
        #expect(ids(d1) == ["bio", "b1", "b2", "b3", "b4"])
        let d2 = GraphFilter(focus: "bio", depth: 2).apply(to: graph)
        #expect(ids(d2) == ids(d1).union(["c3"]))
        let unlimited = GraphFilter(focus: "bio").apply(to: graph)
        #expect(unlimited == graph)
        #expect(GraphFilter(focus: "nope", depth: 3).apply(to: graph).nodes.isEmpty)
        // Depth is measured inside the filtered graph.
        let cut = GraphFilter(courseIDs: ["bio"], focus: "bio", depth: 5).apply(to: graph)
        #expect(ids(cut) == ["bio", "b1", "b2", "b3", "b4"])
    }

    @Test func focusSurvivesOrphanRemoval() {
        let g = GraphFilter(showOrphans: false, focus: "bio", depth: 0).apply(to: graph)
        #expect(ids(g) == ["bio"])
    }

    @Test func combinedFiltersAndOrderPreserved() {
        let f = GraphFilter(courseIDs: ["bio", "chem"], tags: ["exam"], kinds: [.note], showOrphans: false)
        let g = f.apply(to: graph, tagsByNode: tags)
        #expect(ids(g) == ["b1", "c3"])
        let order = GraphFilter(courseIDs: ["hist"]).apply(to: graph).nodes.map(\.id)
        #expect(order == ["hist", "h1", "h2", "h3"])
        // Positions untouched.
        #expect(GraphFilter(courseIDs: ["hist"]).apply(to: graph).nodes[1].x == 300)
    }

    @Test func filterIsPureAndCodable() throws {
        let f = GraphFilter(courseIDs: ["bio"], tags: ["a"], tagMatch: .all, kinds: [.note], showOrphans: false,
                            searchText: "x", focus: "b1", depth: 2)
        let a = f.apply(to: graph), b = f.apply(to: graph)
        #expect(a == b)
        let data = try JSONEncoder().encode(f)
        #expect(try JSONDecoder().decode(GraphFilter.self, from: data) == f)
    }
}
