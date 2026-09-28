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
