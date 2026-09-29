/// A 2D position in canvas units (the design's 1000x800 canvas).
public struct LayoutPoint: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Which part of the vault a graph covers.
public enum GraphScope: Codable, Sendable, Hashable {
    /// Every course, note and unresolved link target.
    case all
    /// One course: its hub, its notes and the link targets first written in its notes. Edges to
    /// other courses are dropped (the subgraph is induced).
    case course(CourseID)
}
