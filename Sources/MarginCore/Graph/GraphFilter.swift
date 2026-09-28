import Foundation

/// How several selected tags combine.
public enum GraphTagMatch: String, Codable, Sendable, Hashable {
    /// A note needs at least one of the tags.
    case any
    /// A note needs all of the tags.
    case all
}

/// Filter model for the knowledge graph: a pure function `Graph -> Graph`.
///
/// Pipeline (in this order):
/// 1. node predicates: kind, course, tags, search text;
/// 2. the induced subgraph (edges whose both ends survive);
/// 3. depth: with a `focus` node and `depth`, only nodes within that many hops of the focus
///    (measured in the subgraph from step 2; an absent focus yields an empty graph);
/// 4. orphans: unless `showOrphans`, nodes without any edge are dropped (the focus is kept).
///
/// Empty sets and `nil`/empty values mean "no restriction". Node order and edge order of the
/// input are preserved, and positions are not touched.
public struct GraphFilter: Codable, Sendable, Hashable {
    /// Keep only nodes of these courses (course hubs own their course id). Empty: all courses.
    public var courseIDs: Set<CourseID>
    /// Keep only notes carrying these tags (see `tagMatch`). Course hubs are not tagged and are
    /// not affected. Empty: no tag restriction.
    public var tags: Set<String>
    public var tagMatch: GraphTagMatch
    /// Keep only these node kinds. Empty: all kinds.
    public var kinds: Set<GraphNodeKind>
    /// Keep orphans (nodes without edges) when true.
    public var showOrphans: Bool
    /// Case- and diacritics-insensitive substring of the node label. Blank: no restriction.
    public var searchText: String
    /// Centre node of a neighbourhood view; used together with `depth`.
    public var focus: String?
    /// Maximum number of hops from `focus` (0 keeps only the focus). `nil`: no depth limit.
    public var depth: Int?

    public init(courseIDs: Set<CourseID> = [], tags: Set<String> = [], tagMatch: GraphTagMatch = .any,
                kinds: Set<GraphNodeKind> = [], showOrphans: Bool = true, searchText: String = "",
                focus: String? = nil, depth: Int? = nil) {
        self.courseIDs = courseIDs; self.tags = tags; self.tagMatch = tagMatch; self.kinds = kinds
        self.showOrphans = showOrphans; self.searchText = searchText; self.focus = focus; self.depth = depth
    }

    /// The filter that keeps everything.
    public static let none = GraphFilter()

    public var isIdentity: Bool { self == GraphFilter() }

    /// Applies the filter. `tagsByNode` maps note ids to their tags (the graph itself carries no
    /// tags); nodes missing from it have no tags. Tags compare case-insensitively.
    public func apply(to graph: Graph, tagsByNode: [String: Set<String>] = [:]) -> Graph {
        let query = Self.fold(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        let wanted = Set(tags.map(Self.fold))
        let normalizedTags = wanted.isEmpty ? [:] : tagsByNode.mapValues { Set($0.map(Self.fold)) }

        func keeps(_ node: GraphNode) -> Bool {
            if !kinds.isEmpty && !kinds.contains(node.kind) { return false }
            if !courseIDs.isEmpty {
                guard let course = node.courseID, courseIDs.contains(course) else { return false }
            }
            if !wanted.isEmpty && node.kind == .note {
                let have = normalizedTags[node.id] ?? []
                switch tagMatch {
                case .any: if have.isDisjoint(with: wanted) { return false }
                case .all: if !wanted.isSubset(of: have) { return false }
                }
            }
            if !query.isEmpty && !Self.fold(node.label).contains(query) { return false }
            return true
        }

        var nodes = graph.nodes.filter(keeps)
        var alive = Set(nodes.map(\.id))
        var edges = graph.edges.filter { alive.contains($0.source) && alive.contains($0.target) }

        if let focus, let depth {
            guard alive.contains(focus) else { return Graph() }
            let reach = Self.reachable(from: focus, within: max(0, depth), edges: edges)
            nodes = nodes.filter { reach.contains($0.id) }
            alive = reach
            edges = edges.filter { alive.contains($0.source) && alive.contains($0.target) }
        }

        if !showOrphans {
            var connected = Set<String>()
            for e in edges where e.source != e.target { connected.insert(e.source); connected.insert(e.target) }
            nodes = nodes.filter { connected.contains($0.id) || $0.id == focus }
        }
        return Graph(nodes: nodes, edges: edges)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func reachable(from start: String, within depth: Int, edges: [GraphEdge]) -> Set<String> {
        var adjacency: [String: [String]] = [:]
        for e in edges {
            adjacency[e.source, default: []].append(e.target)
            adjacency[e.target, default: []].append(e.source)
        }
        var seen: Set<String> = [start]
        var frontier = [start]
        var hops = 0
        while hops < depth && !frontier.isEmpty {
            var next: [String] = []
            for id in frontier {
                for n in adjacency[id] ?? [] where seen.insert(n).inserted { next.append(n) }
            }
            frontier = next; hops += 1
        }
        return seen
    }
}
