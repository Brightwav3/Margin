import Foundation
import Testing
@testable import MarginCore

@Suite struct FixturesWeek5Tests {
    let world = Fixtures.week5

    @Test func countsMatchMockup() {
        #expect(world.courses.count == 6)
        #expect(world.sessions.count == 11)
        #expect(world.dueItems.count == 6)
        #expect(world.exams.count == 3)
        #expect(world.semester.week(of: Fixtures.today) == 5)
        #expect(FixedClock().today == Fixtures.today)
    }

    @Test func courseValues() throws {
        let bio = try #require(world.course("bio"))
        #expect(bio.name == "Cell Biology")
        #expect(bio.code == "BIO 201")
        #expect(bio.professor == "Dr. Okafor")
        #expect(bio.style.dot == "#6FBF7A")
        #expect(world.courses.map(\.id) == ["bio", "chem", "math", "hist", "econ", "phil"])
        #expect(Set(world.courses.map(\.style.color)).count == 6)
    }

    @Test func sessionsAreOrderedAndConsistent() {
        let s = world.sessions
        #expect(s.first?.courseID == "math" && s.first?.day == .monday && s.first?.start == .literal(11))
        #expect(s.last?.courseID == "chem" && s.last?.day == .friday && s.last?.start == .literal(13))
        let lab = s.first { $0.kind == "Lab" }
        #expect(lab?.lengthHours == 3 && lab?.room == "Lab C")
        #expect(s.filter { $0.day == .friday }.count == 3)
        #expect(Set(s.map(\.id)).count == 11)
        for course in world.courses {
            #expect(course.sessions.allSatisfy { $0.courseID == course.id })
        }
    }

    @Test func dueItemsResolveAgainstToday() {
        let due = world.dueItems
        #expect(due.map(\.text) == ["Problem set 4", "Lab report: TLC", "Read chapter 6", "Midterm", "Essay proposal", "Response paper"])
        #expect(due.map(\.label) == [.today, .tomorrow, .weekday(.wednesday), .weekday(.thursday), .weekday(.friday), .weekday(.friday)])
        #expect(due.filter(\.done).map(\.text) == ["Read chapter 6"])
        #expect(due.filter { $0.kind == .exam }.map(\.text) == ["Midterm"])
        #expect(due[0].due == .literal(2026, 9, 28))
        #expect(Set(due.map(\.id)).count == 6)
    }

    @Test func examsOrderedByDate() {
        let e = world.exams
        #expect(e.map(\.title) == ["Midterm", "Quiz 3", "Midterm"])
        #expect(e.map(\.date) == [.literal(2026, 10, 1), .literal(2026, 10, 6), .literal(2026, 10, 14)])
        #expect(e.map(\.weightPercent) == [25, 5, 30])
        #expect(e.map(\.courseID) == ["bio", "econ", "math"])
    }
}

@Suite struct FixturesContentTests {
    let world = Fixtures.week5

    @Test func bioGalleryHasSixCardsInOrder() {
        let g = world.bioGallery
        #expect(g.count == 6)
        #expect(g.map(\.title) == [
            "Lecture 9 — Membrane transport", "Lecture 8 — Cell membrane", "Lecture 7 — Organelles",
            "Lab 2 — Microscopy", "Lecture 6 — Prokaryotes and eukaryotes", "Lecture 5 — Proteins and enzymes"])
        #expect(g.allSatisfy { $0.courseID == "bio" })
        #expect(g[0].isPlaceholder && g[0].date == .literal(2026, 9, 29))
        #expect(g[1].wordCount == 412 && g[1].openTasks == 2)
        #expect(g[3].imageCount == 3 && g[3].kind == .lab)
        #expect(g.map(\.wordCount) == [0, 412, 680, 0, 520, 590])
    }

    @Test func notesAreUniqueAndResolvable() {
        #expect(world.notes.count == 14)
        #expect(Set(world.notes.map(\.id)).count == 14)
        #expect(world.notes.allSatisfy { n in n.courseID.flatMap(world.course) != nil })
        #expect(world.note("bio/lecture-8")?.text.hasPrefix("# Lecture 8 — Cell membrane") == true)
        #expect(world.note("nope") == nil)
    }

    @Test func inboxHasFiveItems() {
        let i = world.inbox
        #expect(i.count == 5)
        #expect(i.map(\.kind) == [.task, .note, .link, .image, .task])
        #expect(i[0].text == "Email Dr. Okafor about lab partner")
        #expect(i[0].captured.iso == "2026-09-28T09:12")
        #expect(i[1].captured.iso == "2026-09-28T08:40")
        #expect(i[4].captured.date == .literal(2026, 9, 26))
        #expect(i[4].captured.date.weekday == .saturday)
    }

    @Test func gradesMatchScreen() {
        let g = world.grades
        #expect(g.count == 6)
        #expect(g.map(\.weightPercent) == [5, 5, 15, 5, 30, 40])
        #expect(g.compactMap(\.weightPercent).reduce(0, +) == 100)
        #expect(g.filter { $0.score != nil }.compactMap(\.weightPercent).reduce(0, +) == 25)
        #expect(g[0].percent == 95 && g[1].percent == 90 && g[2].percent == 88)
        #expect(g[4].date == .literal(2026, 10, 1))
        #expect(world.gradeSummaries.map(\.percent) == [91, 87, 94, 84, 90, 88])
        #expect(world.gradeSummaries.map(\.letter) == ["A−", "B+", "A", "B", "A−", "B+"])
    }
}

@Suite struct FixturesGraphTests {
    let graph = Fixtures.week5.graph

    private func node(_ id: String) -> GraphNode? { graph.nodes.first { $0.id == id } }

    @Test func countsAndIntegrity() {
        #expect(graph.nodes.count == 23)
        #expect(graph.edges.count == 26)
        #expect(graph.nodes.filter { $0.kind == .course }.count == 6)
        let ids = Set(graph.nodes.map(\.id))
        #expect(ids.count == 23)
        #expect(graph.edges.allSatisfy { ids.contains($0.source) && ids.contains($0.target) })
        #expect(Set(graph.edges.map(\.id)).count == 26)
        #expect(graph.nodes.allSatisfy { n in n.courseID.flatMap(Fixtures.week5.course) != nil })
    }

    @Test func exactPositions() {
        let expected: [(String, String, Double, Double)] = [
            ("bio", "Cell Biology", 420, 330), ("b1", "Lecture 8 — Cell membrane", 350, 225),
            ("chem", "Organic Chemistry", 660, 185), ("c2", "Lab 4", 590, 95),
            ("math", "Linear Algebra", 840, 390), ("m2", "Determinants", 920, 470),
            ("hist", "Modern Europe", 390, 630), ("h2", "Congress of Vienna", 470, 735),
            ("econ", "Macroeconomics", 650, 545), ("e1", "IS–LM model", 620, 455),
            ("phil", "Philosophy of Mind", 880, 175), ("p1", "Chinese Room", 950, 95),
        ]
        for (id, label, x, y) in expected {
            let n = node(id)
            #expect(n?.label == label)
            #expect(n?.x == x && n?.y == y)
        }
        #expect(node("bio")?.kind == .course)
        #expect(node("b1")?.kind == .note)
    }

    @Test func edgesFollowMockup() {
        #expect(graph.edges.first == GraphEdge(source: "bio", target: "b1"))
        #expect(graph.edges.last == GraphEdge(source: "b1", target: "b4"))
        #expect(graph.edges.contains(GraphEdge(source: "p1", target: "m1")))
        #expect(graph.edges.filter { $0.source == "bio" }.count == 4)
    }
}

@Suite struct FixturesRoundTripTests {
    private func rt<T: Codable & Equatable>(_ v: T) throws {
        #expect(try JSONDecoder().decode(T.self, from: JSONEncoder().encode(v)) == v)
    }

    @Test func everyFixtureSurvivesJSON() throws {
        let w = Fixtures.week5
        try rt(w.semester); try rt(w.courses); try rt(w.dueItems); try rt(w.notes)
        try rt(w.inbox); try rt(w.grades); try rt(w.gradeSummaries); try rt(w.graph)
    }
}
