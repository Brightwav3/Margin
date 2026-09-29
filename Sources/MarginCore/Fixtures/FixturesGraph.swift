// Knowledge graph of `Fixtures.week5` (M2-05), transcribed 1:1 from `nodes` and `edgeIds` in
// Margin.dc.html: 23 nodes (6 course hubs + 17 notes) and 26 edges, positions in canvas units.
// Node ids are the mockup ids (`bio`, `b1`, …). Edge order follows the mockup.

extension Fixtures {
    private static func node(_ id: String, _ label: String, _ course: CourseID, _ x: Double, _ y: Double,
                             hub: Bool = false) -> GraphNode {
        GraphNode(id: id, label: label, kind: hub ? .course : .note, courseID: course, x: x, y: y)
    }

    static let graph = Graph(
        nodes: [
        node("bio", "Cell Biology", "bio", 420, 330, hub: true),
        node("b1", "Lecture 8 — Cell membrane", "bio", 350, 225),
        node("b2", "Lecture 7 — Organelles", "bio", 300, 390),
        node("b3", "Membrane transport", "bio", 490, 425),
        node("b4", "Glossary", "bio", 520, 265),
        node("chem", "Organic Chemistry", "chem", 660, 185, hub: true),
        node("c1", "Stereochemistry", "chem", 740, 105),
        node("c2", "Lab 4", "chem", 590, 95),
        node("c3", "Lipids", "chem", 575, 300),
        node("math", "Linear Algebra", "math", 840, 390, hub: true),
        node("m1", "Eigenvalues", "math", 910, 300),
        node("m2", "Determinants", "math", 920, 470),
        node("m3", "Matrix basics", "math", 760, 475),
        node("hist", "Modern Europe", "hist", 390, 630, hub: true),
        node("h1", "1848 revolutions", "hist", 300, 715),
        node("h2", "Congress of Vienna", "hist", 470, 735),
        node("h3", "Industrialisation", "hist", 540, 640),
        node("econ", "Macroeconomics", "econ", 650, 545, hub: true),
        node("e1", "IS–LM model", "econ", 620, 455),
        node("e2", "Fiscal policy", "econ", 610, 650),
        node("phil", "Philosophy of Mind", "phil", 880, 175, hub: true),
        node("p1", "Chinese Room", "phil", 950, 95),
        node("p2", "Functionalism", "phil", 820, 85),
        ],
        edges: edgePairs.map { GraphEdge(source: $0.0, target: $0.1) })

    private static let edgePairs: [(String, String)] = [
        ("bio", "b1"), ("bio", "b2"), ("bio", "b3"), ("bio", "b4"),
        ("b1", "b3"), ("b1", "c3"), ("b3", "b4"), ("b2", "b4"),
        ("chem", "c1"), ("chem", "c2"), ("chem", "c3"), ("math", "m1"),
        ("math", "m2"), ("math", "m3"), ("m3", "e1"), ("hist", "h1"),
        ("hist", "h2"), ("hist", "h3"), ("h3", "e2"), ("h3", "econ"),
        ("econ", "e1"), ("econ", "e2"), ("phil", "p1"), ("phil", "p2"),
        ("p1", "m1"), ("b1", "b4"),
    ]
}
