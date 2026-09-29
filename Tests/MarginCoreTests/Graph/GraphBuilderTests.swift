import Foundation
import Testing
@testable import MarginCore

/// M9-01: `GraphBuilder` on the sample vault of `Fixtures.week5` and on hand-made inputs.
@Suite struct GraphBuilderTests {
    let world = Fixtures.week5

    /// Graph labels are shorter than note titles ("Membrane transport" / "Membrane transport summary").
    static func norm(_ s: String) -> String {
        var t = s.lowercased()
        if t.hasPrefix("the ") { t.removeFirst(4) }
        if t.hasSuffix(" summary") { t.removeLast(8) }
        return t
    }

    struct Vault {
        let dir: TempDir
        let index: NoteIndex
        let courses: [Course]
        let courseOf: @Sendable (NoteRecord) -> CourseID?
    }

    private func sampleVault() async throws -> Vault {
        let dir = TempDir()
        let clock = FixedClock()
        let store = try await VaultStore.open(root: dir.url, clock: clock, trash: PortableTrash())
        try await SampleVaultGenerator.generate(into: store, from: world)
        let index = NoteIndex(clock: clock)
        _ = try await index.build(from: VaultNoteSource(store: store))
        let model = await VaultCourseModel.load(from: store, clock: clock)
        return Vault(dir: dir, index: index, courses: ServiceRules.sortCourses(model.courses),
                     courseOf: { model.courseID(semesterFolder: $0.semesterID, folder: $0.courseID, className: $0.className) })
    }

    private func build(_ v: Vault, _ options: GraphBuildOptions = GraphBuildOptions()) async -> GraphSnapshot {
        await GraphBuilder.build(index: v.index, courses: v.courses, options: options,
                                 isNote: { VaultBackend.isNotePath($0.path) }, courseOf: v.courseOf)
    }

    /// The note ids of the vault whose title matches a node label of the fixture graph.
    private func fixtureNoteIDs(_ v: Vault) async -> Set<NoteID> {
        let labels = Set(world.graph.nodes.filter { $0.kind == .note }.map { Self.norm($0.label) })
        return Set(await v.index.allNotes.filter { VaultBackend.isNotePath($0.path) && labels.contains(Self.norm($0.title)) }.map(\.id))
    }

    /// Nodes of the mockup graph that the sample vault cannot produce: notes that are not created
    /// yet and that no note links to (the sample notes only link along the mockup's note-to-note
    /// edges, and a course hub edge is a folder relation, not a link).
    static let unreachableInSampleVault: Set<String> = [
        "lab 4", "congress of vienna", "industrialisation", "fiscal policy", "functionalism", "matrix basics",
    ]

    @Test func sampleVaultGraphMatchesTheFixtureGraphNodeSet() async throws {
        let v = try await sampleVault(); defer { withExtendedLifetime(v) {} }
        let only = await fixtureNoteIDs(v)
        #expect(only.count == 9)   // the mockup draws 9 of the 14 notes (19 files with the assignment notes)
        let g = await build(v, GraphBuildOptions(onlyNotes: only)).graph

        let builtLabels = Set(g.nodes.map { Self.norm($0.label) })
        let fixtureLabels = Set(world.graph.nodes.map { Self.norm($0.label) })
        #expect(g.nodes.count == 17)
        #expect(Set(g.nodes.map(\.id)).count == 17)
        #expect(g.nodes.filter { $0.kind == .course }.count == 6)
        // Exactly 23 - 6: nothing extra, and only the unreachable nodes are missing.
        #expect(builtLabels.isSubset(of: fixtureLabels))
        #expect(fixtureLabels.subtracting(builtLabels) == Self.unreachableInSampleVault)
        #expect(builtLabels.count + Self.unreachableInSampleVault.count == world.graph.nodes.count)   // 17 + 6 = 23

        // Real notes keep the fixture course; a ghost takes the course of the note that links to it.
        let fixtureCourse = Dictionary(uniqueKeysWithValues: world.graph.nodes.map { (Self.norm($0.label), $0.courseID) })
        for n in g.nodes where !n.id.hasPrefix("ghost:") { #expect(n.courseID == fixtureCourse[Self.norm(n.label)], "\(n.label)") }
        let ids = Set(g.nodes.map(\.id))
        #expect(g.edges.allSatisfy { ids.contains($0.source) && ids.contains($0.target) && $0.source != $0.target })
        #expect(Set(g.edges.map { [$0.source, $0.target].sorted() }).count == g.edges.count)
    }

    @Test func edgesAreTheFixtureEdgesBetweenTheBuiltNodes() async throws {
        let v = try await sampleVault(); defer { withExtendedLifetime(v) {} }
        let g = await build(v, GraphBuildOptions(onlyNotes: await fixtureNoteIDs(v))).graph
        let label = Dictionary(uniqueKeysWithValues: g.nodes.map { ($0.id, Self.norm($0.label)) })
        let built = Set(g.edges.map { [label[$0.source]!, label[$0.target]!].sorted() })

        let fixtureLabel = Dictionary(uniqueKeysWithValues: world.graph.nodes.map { ($0.id, Self.norm($0.label)) })
        let expected = Set(world.graph.edges.map { [fixtureLabel[$0.source]!, fixtureLabel[$0.target]!].sorted() })
        let present = Set(label.values)
        let expectedHere = expected.filter { $0.allSatisfy(present.contains) }
        let missing = expectedHere.subtracting(built), extra = built.subtracting(expected)
        print("graph edges: built \(built.count), fixture between built nodes \(expectedHere.count), missing \(missing.sorted { $0.joined() < $1.joined() }), extra \(extra.sorted { $0.joined() < $1.joined() })")
        // Ghosts get no hub edge (their course is only a guess), so the hub edges of Lipids and
        // Eigenvalues are the only mockup edges between built nodes that are absent.
        #expect(missing == Set([["eigenvalues", "linear algebra"], ["lipids", "organic chemistry"]]))
        #expect(extra.isEmpty)
    }

    @Test func fullGraphHasEveryNoteFileAndTheGhosts() async throws {
        let v = try await sampleVault(); defer { withExtendedLifetime(v) {} }
        let snap = await build(v)
        let stats = GraphStatistics(snap.graph)
        let ghosts = snap.graph.nodes.filter { $0.id.hasPrefix("ghost:") }
        #expect(stats.hubCount == 6)
        #expect(ghosts.count == 2)   // Lipids and Eigenvalues, the only targets no note exists for
        #expect(Set(ghosts.map { Self.norm($0.label) }) == ["lipids", "eigenvalues"])
        #expect(stats.noteCount == world.allNotes.count + ghosts.count)
        // Every real note is in the graph with its fixture id and its hub edge.
        for note in world.allNotes {
            #expect(snap.graph.nodes.contains { $0.id == note.id && $0.courseID == note.courseID }, "\(note.id)")
            #expect(snap.graph.edges.contains(GraphEdge(source: note.courseID!, target: note.id)), "\(note.id)")
        }
        #expect(stats.edgeCount == snap.graph.edges.count)
        #expect(stats.degree.values.reduce(0, +) == 2 * stats.edgeCount)
    }

    @Test func optionsSwitchGhostsAndCourseEdgesOff() async throws {
        let v = try await sampleVault(); defer { withExtendedLifetime(v) {} }
        let plain = await build(v, GraphBuildOptions(includeUnresolved: false, includeCourseEdges: false)).graph
        #expect(plain.nodes.count == 6 + world.allNotes.count)
        #expect(plain.nodes.allSatisfy { !$0.id.hasPrefix("ghost:") })
        #expect(plain.edges.allSatisfy { e in !plain.nodes.contains { $0.id == e.source && $0.kind == .course } })
        #expect(!plain.edges.isEmpty)
    }

    @Test func buildIsDeterministic() async throws {
        let v = try await sampleVault(); defer { withExtendedLifetime(v) {} }
        let a = await build(v), b = await build(v)
        #expect(a == b)
    }

    // MARK: Hand-made inputs

    private let courses = [
        Course(id: "c1", semester: "s", name: "One", code: "C1", style: CourseStyle(icon: "", color: "bio", background: "", foreground: "", dot: "")),
        Course(id: "c2", semester: "s", name: "Two", code: "C2", style: CourseStyle(icon: "", color: "bio", background: "", foreground: "", dot: "")),
    ]

    @Test func handMadeGraphDedupesAndSkipsSelfAndAmbiguous() {
        let inputs = [
            GraphNoteInput(id: "c1/a", title: "A", courseID: "c1", tags: ["x"], links: [.resolved("c1/b"), .resolved("c1/b"), .selfLink, .resolved("c1/a")]),
            GraphNoteInput(id: "c1/b", title: "B", courseID: "c1", tags: [], links: [.resolved("c1/a"), .ambiguous(["c2/c", "c1/a"])]),
            GraphNoteInput(id: "c2/c", title: "C", courseID: "nope", tags: ["X", "y"], links: [.notCreated(target: "Later")],
                           unresolvedLabels: ["Later": "Later"]),
        ]
        let s = GraphBuilder.build(inputs: inputs, courses: courses, options: GraphBuildOptions())
        #expect(s.graph.nodes.map(\.id) == ["c1", "c2", "c1/a", "c1/b", "c2/c", "ghost:later"])
        #expect(s.graph.nodes.first { $0.id == "c2/c" }?.courseID == nil)   // unknown course id is dropped
        #expect(s.graph.edges == [
            GraphEdge(source: "c1", target: "c1/a"), GraphEdge(source: "c1", target: "c1/b"),
            GraphEdge(source: "c1/a", target: "c1/b"), GraphEdge(source: "c1/b", target: "c2/c"),
            GraphEdge(source: "c2/c", target: "ghost:later"),
        ])
        #expect(s.tagsByNode == ["c1/a": ["x"], "c2/c": ["X", "y"]])
        let stats = GraphStatistics(s.graph)
        #expect(stats.degree["c1/b"] == 3 && stats.degree["c2"] == 0 && stats.orphanCount == 1)
        #expect(stats.nodeCount == 6 && stats.edgeCount == 5 && stats.hubCount == 2 && stats.noteCount == 4)
    }

    @Test func emptyInputGivesHubsOnly() {
        let s = GraphBuilder.build(inputs: [], courses: courses, options: GraphBuildOptions())
        #expect(s.graph.nodes.map(\.id) == ["c1", "c2"] && s.graph.edges.isEmpty)
        #expect(GraphBuilder.build(inputs: [], courses: [], options: GraphBuildOptions()).graph == Graph())
    }
}
