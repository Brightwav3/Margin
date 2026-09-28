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
