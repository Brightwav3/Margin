import Foundation

/// What `GraphBuilder` puts into the graph.
public struct GraphBuildOptions: Sendable, Hashable {
    /// Add a node for every link whose target note does not exist yet ("Not created yet").
    public var includeUnresolved = true
    /// Add an edge from the course hub to each of its notes.
    public var includeCourseEdges = true
    /// Restrict the note nodes to these notes (`nil`: every note). Links to notes outside the set
    /// are dropped as well; hubs are kept.
    public var onlyNotes: Set<NoteID>?

    public init(includeUnresolved: Bool = true, includeCourseEdges: Bool = true, onlyNotes: Set<NoteID>? = nil) {
        self.includeUnresolved = includeUnresolved; self.includeCourseEdges = includeCourseEdges
        self.onlyNotes = onlyNotes
    }
}

/// A built graph plus the per-note tags `GraphFilter` needs (the graph itself carries none).
public struct GraphSnapshot: Sendable, Hashable {
    public var graph: Graph
    /// Note id -> tags.
    public var tagsByNode: [String: Set<String>]

    public init(graph: Graph = Graph(), tagsByNode: [String: Set<String>] = [:]) {
        self.graph = graph; self.tagsByNode = tagsByNode
    }
}

/// The note as the builder sees it: no file, no text, just identity and resolved links.
struct GraphNoteInput: Sendable, Hashable {
    var id: NoteID
    var title: String
    var courseID: CourseID?
    var tags: [String]
    var links: [WikilinkResolution]
    /// Display text of each unresolved link target (keyed by the normalised target).
    var unresolvedLabels: [String: String] = [:]
}

/// Builds the knowledge graph (M9-01) from the note index.
///
/// - **Nodes:** one hub per course (id = course id, `kind == .course`), one node per note (id =
///   note id), and, with `includeUnresolved`, one "ghost" note node per link target that has no
///   note yet (id `ghost:<normalised target>`, course of the first note that links to it).
/// - **Edges:** one per pair of notes that link to each other in either direction (a wikilink;
///   the first direction found is kept, order is by note id); hub -> note for each note that
///   belongs to a course; note -> ghost. Self links, embeds (`![[image.png]]`) and duplicates
///   are ignored. An ambiguous link produces an edge to every candidate.
/// - **Order:** hubs (as given), then notes by id, then ghosts by id; edges: course edges first
///   (by course, then note), then link edges by source and target id. Deterministic.
/// - **Positions** are all 0; use `ForceLayout` (or `GraphService.layout`) to place the nodes.
public enum GraphBuilder {
    /// Id of the ghost node for an unresolved link target.
    public static func ghostID(forTarget target: String) -> String {
        "ghost:" + WikilinkExtractor.normalise(target)
    }

    /// Builds the graph of everything in `index` that `isNote` accepts.
    ///
    /// - Parameters:
    ///   - courseOf: maps a record to its course (`nil`: no course, no hub edge). The vault passes
    ///     the course model; the default trusts the folder-derived id when a course of that id exists.
    public static func build(index: NoteIndex, courses: [Course], options: GraphBuildOptions = GraphBuildOptions(),
                             isNote: @Sendable (NoteRecord) -> Bool = { _ in true },
                             courseOf: @Sendable (NoteRecord) -> CourseID? = { $0.courseID }) async -> GraphSnapshot {
        var inputs: [GraphNoteInput] = []
        for record in await index.allNotes where isNote(record) {
            var links: [WikilinkResolution] = []
            var labels: [String: String] = [:]
            for (link, resolution) in await index.outgoingLinks(ofPath: record.path) where !link.isEmbed {
                links.append(resolution)
                if case .notCreated(let target) = resolution { labels[target] = labels[target] ?? link.name }
            }
            inputs.append(GraphNoteInput(id: record.id, title: record.title, courseID: courseOf(record),
                                         tags: record.tags, links: links, unresolvedLabels: labels))
        }
        return build(inputs: inputs, courses: courses, options: options)
    }

    static func build(inputs: [GraphNoteInput], courses: [Course], options: GraphBuildOptions) -> GraphSnapshot {
        let courseIDs = Set(courses.map(\.id))
        var nodes: [GraphNode] = courses.map {
            GraphNode(id: $0.id, label: $0.name, kind: .course, courseID: $0.id, x: 0, y: 0)
        }
        let notes = inputs
            .filter { options.onlyNotes?.contains($0.id) ?? true }
            .sorted { $0.id < $1.id }
        let noteIDs = Set(notes.map(\.id))
        var tags: [String: Set<String>] = [:]
        var courseEdges: [GraphEdge] = []
        for note in notes {
            let course = note.courseID.flatMap { courseIDs.contains($0) ? $0 : nil }
            nodes.append(GraphNode(id: note.id, label: note.title, kind: .note, courseID: course, x: 0, y: 0))
            if !note.tags.isEmpty { tags[note.id] = Set(note.tags) }
            if options.includeCourseEdges, let course { courseEdges.append(GraphEdge(source: course, target: note.id)) }
        }
        courseEdges.sort { ($0.source, $0.target) < ($1.source, $1.target) }

        // Links.
        var linkEdges: [String: GraphEdge] = [:]   // key: unordered pair
        var ghosts: [String: GraphNode] = [:]
        func add(_ a: String, _ b: String) {
            guard a != b else { return }
            let key = a < b ? "\(a)\u{0}\(b)" : "\(b)\u{0}\(a)"
            if linkEdges[key] == nil { linkEdges[key] = GraphEdge(source: a, target: b) }
        }
        for note in notes {
            for resolution in note.links {
                switch resolution {
                case .resolved(let id): if noteIDs.contains(id) { add(note.id, id) }
                case .ambiguous(let ids): for id in ids where noteIDs.contains(id) { add(note.id, id) }
                case .notCreated(let target):
                    guard options.includeUnresolved, !target.isEmpty else { continue }
                    let id = ghostID(forTarget: target)
                    if ghosts[id] == nil {
                        ghosts[id] = GraphNode(id: id, label: note.unresolvedLabels[target] ?? target, kind: .note,
                                               courseID: note.courseID.flatMap { courseIDs.contains($0) ? $0 : nil },
                                               x: 0, y: 0)
                    }
                    add(note.id, id)
                case .selfLink: break
                }
            }
        }
        nodes += ghosts.values.sorted { $0.id < $1.id }
        let sortedLinks = linkEdges.values.sorted { ($0.source, $0.target) < ($1.source, $1.target) }
        return GraphSnapshot(graph: Graph(nodes: nodes, edges: courseEdges + sortedLinks), tagsByNode: tags)
    }
}

/// Counts over a graph: degree per node and totals (M9-01 "counts").
public struct GraphStatistics: Sendable, Hashable {
    /// Number of edges at each node (self loops count once). Every node has an entry.
    public let degree: [String: Int]
    public let nodeCount: Int
    public let edgeCount: Int
    public let hubCount: Int
    public let noteCount: Int
    /// Nodes without any edge.
    public let orphanCount: Int
    /// Note nodes per course id (hubs are not counted).
    public let notesPerCourse: [CourseID: Int]

    public init(_ graph: Graph) {
        var deg: [String: Int] = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, 0) })
        for e in graph.edges {
            if deg[e.source] != nil { deg[e.source]! += 1 }
            if e.target != e.source, deg[e.target] != nil { deg[e.target]! += 1 }
        }
        degree = deg
        nodeCount = graph.nodes.count
        edgeCount = graph.edges.count
        hubCount = graph.nodes.filter { $0.kind == .course }.count
        noteCount = nodeCount - hubCount
        orphanCount = deg.values.filter { $0 == 0 }.count
        var per: [CourseID: Int] = [:]
        for n in graph.nodes where n.kind == .note { if let c = n.courseID { per[c, default: 0] += 1 } }
        notesPerCourse = per
    }
}
