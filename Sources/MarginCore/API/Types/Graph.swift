/// Node type in the knowledge graph.
public enum GraphNodeKind: String, Codable, Sendable, Hashable {
    /// A course hub.
    case course
    case note
}

/// A graph node with a layout position in the design's 1000x800 canvas units.
///
/// Invariant: `id` unique within a graph. `courseID` is set for every node (hubs own their id).
public struct GraphNode: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var label: String
    public var kind: GraphNodeKind
    public var courseID: CourseID?
    public var x: Double
    public var y: Double

    public init(id: String, label: String, kind: GraphNodeKind, courseID: CourseID? = nil, x: Double, y: Double) {
        self.id = id; self.label = label; self.kind = kind; self.courseID = courseID; self.x = x; self.y = y
    }
}

/// An undirected link between two nodes. Invariant: both ids exist in the graph.
public struct GraphEdge: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(source)--\(target)" }
    public var source: String
    public var target: String

    public init(source: String, target: String) {
        self.source = source; self.target = target
    }
}

public struct Graph: Codable, Sendable, Hashable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    public init(nodes: [GraphNode] = [], edges: [GraphEdge] = []) {
        self.nodes = nodes; self.edges = edges
    }
}
