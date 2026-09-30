import MarginCore
import Observation
import SwiftUI

/// Graph map (4a, M9): the semester's notes and links, course filters, orphans, a local graph
/// around one note, zoom/pan and the preview of the selected node.
@MainActor @Observable
public final class GraphModel {
    public private(set) var graph = Graph()
    /// Positions shown (the backend's, then the force layout's snapshots when there are none).
    public private(set) var positions: [String: CGPoint] = [:]
    public var hiddenCourses: Set<CourseID> = [] { didSet { Task { await reload() } } }
    public var showOrphans = true { didSet { Task { await reload() } } }
    /// Local graph: a note in the middle and its neighbours up to `depth` hops.
    public var focus: NoteID? { didSet { Task { await reload() } } }
    public var depth = 1 { didSet { if focus != nil { Task { await reload() } } } }
    public var selected: String?
    public var hovered: String?
    public var zoom: CGFloat = 1
    public var offset: CGSize = .zero
    public private(set) var isLoaded = false
    public private(set) var excerpt: NoteExcerpt?

    private let env: AppEnvironment
    private var layoutTask: Task<Void, Never>?
    /// Canvas size of the backend coordinates (mockup: 1004 × 820 with the SVG offset 40, −40).
    static let canvas = CGSize(width: 1004, height: 820)

    public init(env: AppEnvironment, focus: NoteID? = nil) {
        self.env = env
        self.focus = focus
    }

    public func load() async { await reload() }

    private func reload() async {
        let courses = (try? await env.courses.courses(query: nil)) ?? []
        let visible = Set(courses.map(\.id)).subtracting(hiddenCourses)
        var filter = GraphFilter(courseIDs: hiddenCourses.isEmpty ? [] : visible, showOrphans: showOrphans)
        if let focus { filter.focus = focus; filter.depth = depth }
        do {
            graph = try await env.graph.graph(scope: .all, filter: filter)
        } catch {
            graph = Graph()
        }
        positions = Dictionary(graph.nodes.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) }, uniquingKeysWith: { a, _ in a })
        isLoaded = true
        // Nodes without a position (all at 0,0) get the force layout, animated.
        if graph.nodes.count > 1, Set(graph.nodes.map { "\($0.x),\($0.y)" }).count <= 1 || focus != nil {
            runLayout()
        }
    }

    private func runLayout() {
        layoutTask?.cancel()
        let g = graph
        layoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await snapshot in self.env.graph.layout(g) {
                if Task.isCancelled { return }
                self.positions = snapshot.mapValues { CGPoint(x: $0.x, y: $0.y) }
            }
        }
    }

    public var noteCount: Int { graph.nodes.filter { $0.kind == .note }.count }

    /// Neighbours of the hovered or selected node (highlighted edges).
    public var hot: Set<String> {
        guard let id = hovered ?? selected else { return [] }
        var set: Set<String> = [id]
        for e in graph.edges where e.source == id || e.target == id { set.insert(e.source); set.insert(e.target) }
        return set
    }

    public func degree(_ id: String) -> Int { graph.edges.filter { $0.source == id || $0.target == id }.count }

    public var selectedNode: GraphNode? { graph.nodes.first { $0.id == selected } }

    public func select(_ id: String?) {
        selected = id
        excerpt = nil
        guard let id, let node = graph.nodes.first(where: { $0.id == id }), node.kind == .note else { return }
        Task { @MainActor in
            let e = try? await env.search.excerpt(note: id, heading: nil)
            if selected == id { excerpt = e }
        }
    }

    /// Screen point of a node for the current zoom and pan inside `size`.
    func point(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let fit = fitScale(size)
        let s = fit * zoom
        // Centred in the space right of the filter panel (220 px at 32 px from the edge).
        let cx = (size.width + 252) / 2, cy = size.height / 2 + 30
        let bx = bounds.midX, by = bounds.midY
        return CGPoint(x: cx + (p.x - bx) * s + offset.width, y: cy + (p.y - by) * s + offset.height)
    }

    /// Node under a screen point (hit radius grows with the node).
    func node(at location: CGPoint, in size: CGSize) -> GraphNode? {
        var best: (GraphNode, CGFloat)?
        for n in graph.nodes {
            guard let p = positions[n.id] else { continue }
            let q = point(p, in: size)
            let d = hypot(q.x - location.x, q.y - location.y)
            let r = radius(n) * max(1, zoom) + 6
            if d <= r, d < (best?.1 ?? .infinity) { best = (n, d) }
        }
        return best?.0
    }

    var bounds: CGRect {
        let pts = positions.values
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else {
            return CGRect(origin: .zero, size: Self.canvas)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    /// Scale that fits all nodes with a margin for labels (fit-to-screen at zoom 1).
    func fitScale(_ size: CGSize) -> CGFloat {
        let b = bounds
        let sx = (size.width - 252 - 160) / b.width, sy = (size.height - 220) / b.height
        return max(0.05, min(1.6, min(sx, sy)))
    }

    public func fit() { zoom = 1; offset = .zero }
    public func zoomIn() { zoom = min(6, zoom * 1.25) }
    public func zoomOut() { zoom = max(0.2, zoom / 1.25) }

    func radius(_ n: GraphNode) -> CGFloat {
        if n.kind == .course { return 10 }
        return n.id == focus || n.id == selected ? 7 : 5
    }

    /// Labels: hubs always; notes when zoomed in enough or the graph is small (M9-09 LOD).
    func showsLabel(_ n: GraphNode) -> Bool {
        n.kind == .course || hot.contains(n.id) || (graph.nodes.count < 300 ? zoom >= 0.6 : zoom >= 1.6)
    }
}
