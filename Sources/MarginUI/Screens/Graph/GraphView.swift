import MarginCore
import SwiftUI

/// 4a Graph map: canvas `#FAFAFB`, title and counts, floating filters, zoom buttons, preview card.
struct GraphView: View {
    @Bindable var model: GraphModel
    @Environment(Workspace.self) private var workspace
    @State private var dragStart: CGSize?
    @State private var zoomStart: CGFloat?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(hex: 0xFAFAFB)
                canvas(geo.size)
                    .gesture(pan.simultaneously(with: magnify))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): model.hovered = model.node(at: p, in: geo.size)?.id
                        case .ended: model.hovered = nil
                        }
                    }
                    .onTapGesture(coordinateSpace: .local) { p in model.select(model.node(at: p, in: geo.size)?.id) }
                    .gesture(TapGesture(count: 2).onEnded { open(model.selectedNode) })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Graph of \(model.noteCount) notes and \(model.graph.edges.count) links")
                    .accessibilityChildren {
                        ForEach(model.graph.nodes) { n in
                            Button(n.label) { open(n) }
                                .accessibilityHint(n.kind == .course ? "Course" : "\(model.degree(n.id)) links")
                        }
                    }
                    .background(ScrollZoom { dy in
                        model.zoom = min(6, max(0.2, model.zoom * (1 - dy / 300)))
                    })
                header.padding(32)
                filters.padding(.leading, 32).padding(.top, 120)
                controls
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(32)
                if let node = model.selectedNode { preview(node).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(32) }
            }
        }
        .task { await model.load() }
    }

    // MARK: Canvas

    private func canvas(_ size: CGSize) -> some View {
        let hot = model.hot
        // Colours per course, resolved once per frame instead of once per node.
        let palette = Dictionary(workspace.courses.cards.map { card in
            (card.id, (dot: Color(hexString: card.course.style.dot), background: Color(hexString: card.course.style.background)))
        }, uniquingKeysWith: { a, _ in a })
        let grey = (dot: Color(hexString: "#9A9DA6"), background: Color(hexString: "#E9EAEE"), ring: Color(hexString: "#C4C7CF"))
        let positions = model.positions
        return Canvas { ctx, _ in
            let project = model.projection(in: size)
            // Plain edges in one path, highlighted ones in another: two strokes instead of thousands.
            var plain = Path(), lit = Path()
            for e in model.graph.edges {
                guard let a = positions[e.source], let b = positions[e.target] else { continue }
                let isHot = !hot.isEmpty && hot.contains(e.source) && hot.contains(e.target)
                if isHot { lit.move(to: project(a)); lit.addLine(to: project(b)) }
                else { plain.move(to: project(a)); plain.addLine(to: project(b)) }
            }
            ctx.stroke(plain, with: .color(Color(hex: 0xD5D7DD)), lineWidth: 1)
            ctx.stroke(lit, with: .color(Color(hex: 0x8FB0F3)), lineWidth: 1.5)
            let visible = CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40)
            for n in model.graph.nodes {
                guard let p0 = positions[n.id] else { continue }
                let p = project(p0)
                guard visible.contains(p) else { continue }
                let style = n.courseID.flatMap { palette[$0] }
                let r = model.radius(n)
                let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
                let isFocus = n.id == model.selected || n.id == model.focus
                let dim = !hot.isEmpty && !hot.contains(n.id)
                let fill: Color = isFocus ? MarginColor.accent
                    : n.kind == .course ? (style?.dot ?? grey.dot)
                    : (style?.background ?? grey.background)
                let stroke: Color = isFocus ? MarginColor.accentRing : (style?.dot ?? grey.ring)
                ctx.opacity = dim ? 0.35 : 1
                ctx.fill(Path(ellipseIn: rect), with: .color(fill))
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: isFocus ? -2 : 0, dy: isFocus ? -2 : 0)), with: .color(stroke), lineWidth: isFocus ? 4 : 1.5)
                if model.showsLabel(n, hot: hot) {
                    let text = Text(n.label)
                        .font(.margin(n.kind == .course ? 13 : 12, n.kind == .course ? .semibold : .regular))
                        .foregroundColor(isFocus ? MarginColor.accentText : n.kind == .course ? MarginColor.ink : MarginColor.textSecondary)
                    ctx.draw(text, at: CGPoint(x: p.x, y: p.y + r + 10), anchor: .center)
                }
                ctx.opacity = 1
            }
        }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if dragStart == nil { dragStart = model.offset }
                model.offset = CGSize(width: (dragStart?.width ?? 0) + v.translation.width,
                                      height: (dragStart?.height ?? 0) + v.translation.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if zoomStart == nil { zoomStart = model.zoom }
                model.zoom = min(6, max(0.2, (zoomStart ?? 1) * v.magnification))
            }
            .onEnded { _ in zoomStart = nil }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.focus == nil ? "Graph map" : "Local graph").marginFont(MarginTextSize.page, .bold).tracking(-0.6)
            Text("\(model.noteCount) notes · \(model.graph.edges.count) links")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
        }
        .allowsHitTesting(false)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.focus != nil {
                Text("Depth").marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textSecondary)
                Segmented([(1, "1 link"), (2, "2 links"), (3, "3 links")], selection: $model.depth).fixedSize()
                Button("Show whole semester") { model.focus = nil }
                    .buttonStyle(.plain).foregroundStyle(MarginColor.accentText).marginFont(MarginTextSize.sm)
                MarginDivider().padding(.vertical, 4)
            }
            Text("Courses").marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textSecondary)
            ForEach(workspace.courses.cards) { card in
                let on = !model.hiddenCourses.contains(card.id)
                HStack(spacing: 10) {
                    CheckboxView(isOn: Binding(get: { on }, set: { v in
                        if v { model.hiddenCourses.remove(card.id) } else { model.hiddenCourses.insert(card.id) }
                    }), label: "Show \(card.course.name)")
                    Circle().fill(Color(hexString: card.course.style.dot)).frame(width: 8, height: 8)
                    Text(card.course.name).marginFont(MarginTextSize.base).lineLimit(1)
                }
            }
            MarginDivider().padding(.vertical, 4)
            HStack {
                Text("Show tasks").marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textDisabled)
                Spacer()
                SwitchView(isOn: .constant(false)).disabled(true)
            }
            .help("Tasks are not nodes of the graph yet (GraphService has notes and courses)")
            HStack {
                Text("Orphan notes").marginFont(MarginTextSize.base)
                Spacer()
                SwitchView(isOn: $model.showOrphans, label: "Orphan notes")
            }
        }
        .padding(16)
        .frame(width: 220, alignment: .leading)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.borderCard) }
        .shadow(color: MarginColor.ink.opacity(0.06), radius: 8, y: 4)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            square("remove", "Zoom out") { withAnimation(Shell.motion(.easeOut(duration: 0.15))) { model.zoomOut() } }
            square("add", "Zoom in") { withAnimation(Shell.motion(.easeOut(duration: 0.15))) { model.zoomIn() } }
            square("center_focus_weak", "Fit to screen") { withAnimation(Shell.motion(.easeOut(duration: 0.2))) { model.fit() } }
        }
    }

    private func square(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 20, color: MarginColor.ink)
                .frame(width: 40, height: 40)
                .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
                .overlay { RoundedRectangle(cornerRadius: MarginRadius.sm).strokeBorder(MarginColor.border) }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func preview(_ node: GraphNode) -> some View {
        let course = node.courseID.flatMap { workspace.courses.course(id: $0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Color(hexString: course?.style.dot ?? "#9A9DA6")).frame(width: 8, height: 8)
                Text(node.kind == .course ? "Course" : "\(course?.name ?? "Note")")
            }
            .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
            Text(node.label).marginFont(MarginTextSize.md, .semibold)
            if let e = model.excerpt, !e.isEmpty {
                Text(e.text).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary).lineSpacing(2).lineLimit(4)
            }
            HStack(spacing: 8) {
                Text("\(model.degree(node.id)) links").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                Spacer()
                if node.kind == .note {
                    MarginButton("Local graph", size: .small) { model.focus = node.id }
                }
                MarginButton("Open", kind: .primary, size: .small) { open(node) }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.borderCard) }
        .shadow(color: MarginColor.ink.opacity(0.08), radius: 12, y: 8)
    }

    private func open(_ node: GraphNode?) {
        guard let node else { return }
        switch node.kind {
        case .course: if let c = workspace.courses.course(id: node.id) { workspace.open(course: c) }
        case .note: workspace.open(.note(node.id), title: node.label)
        }
    }
}

/// Scroll wheel / trackpad scroll zooms the graph.
private struct ScrollZoom: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollCatcher {
        let v = ScrollCatcher()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ v: ScrollCatcher, context: Context) { v.onScroll = onScroll }

    final class ScrollCatcher: NSView {
        var onScroll: (CGFloat) -> Void = { _ in }
        private var monitor: Any?

        // The monitor is removed when the view leaves its window. Not in `removeFromSuperview`:
        // AppKit calls that from `dealloc`, when Swift properties are already gone (crash).
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window == window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return event }
                self.onScroll(event.scrollingDeltaY)
                return nil
            }
        }
    }
}
