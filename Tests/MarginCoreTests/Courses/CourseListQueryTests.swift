import Foundation
import Testing
@testable import MarginCore

/// M3-04: sorting and filtering of the course list on `Fixtures.week5` (Monday 28 Sep 2026, 13:24).
@Suite struct CourseListQueryTests {
    let world = Fixtures.week5
    let now = LocalDateTime(date: .literal(2026, 9, 28), time: .literal(13, 24))

    /// Two more faculties on top of the fixture (only Cell Biology has one there).
    var courses: [Course] {
        world.courses.map { c in
            var c = c
            switch c.id {
            case "chem": c.faculty = "Sciences"
            case "math": c.faculty = "Mathematics"
            case "econ": c.faculty = "Social Sciences"
            default: break
            }
            return c
        }
    }

    // Open due tasks per course, as the task service would count them.
    var context: CourseListQuery.Context {
        CourseListQuery.Context(now: now, dueCounts: ["math": 3, "chem": 1, "bio": 1, "hist": 0])
    }

    private func ids(_ q: CourseListQuery) -> [CourseID] { q.apply(to: courses, context: context).map(\.id) }

    @Test func defaultQuerySortsByNameLikeTheCatalog() {
        #expect(ids(.default) == ["bio", "math", "econ", "hist", "chem", "phil"])
        #expect(ids(.default) == ServiceRules.sortCourses(courses).map(\.id))
    }

    @Test func sortsByCodeAscendingAndDescending() {
        // BIO 201, CHEM 230, ECON 102, HIST 210, MATH 221, PHIL 240
        #expect(ids(CourseListQuery(sortBy: .code)) == ["bio", "chem", "econ", "hist", "math", "phil"])
        #expect(ids(CourseListQuery(sortBy: .code, descending: true)) == ["phil", "math", "hist", "econ", "chem", "bio"])
    }

    @Test func sortsByNextSession() {
        // chem Mon 14:00 (today), bio Tue 10:00, econ Tue 15:00, math Wed 11:00, hist Wed 13:00, phil Thu 16:00.
        #expect(ids(CourseListQuery(sortBy: .nextSession)) == ["chem", "bio", "econ", "math", "hist", "phil"])
        #expect(ids(CourseListQuery(sortBy: .nextSession, descending: true)) == ["phil", "hist", "math", "econ", "bio", "chem"])
    }

    @Test func aSessionThatAlreadyStartedTodayMovesToNextWeek() {
        // Math Monday 11:00 is over at 13:24, so its next session is Wednesday.
        let math = courses.first { $0.id == "math" }!
        #expect(CourseSchedule.nextSession(of: math, after: now) == LocalDateTime(date: .literal(2026, 9, 30), time: .literal(11)))
        // Starting exactly now counts as upcoming; one minute later it does not.
        let chem = courses.first { $0.id == "chem" }!
        let atStart = LocalDateTime(date: .literal(2026, 9, 28), time: .literal(14, 0))
        #expect(CourseSchedule.nextSession(of: chem, after: atStart) == atStart)
        let after = LocalDateTime(date: .literal(2026, 9, 28), time: .literal(14, 1))
        #expect(CourseSchedule.nextSession(of: chem, after: after) == LocalDateTime(date: .literal(2026, 10, 2), time: .literal(13)))
        // Sunday: everything is ahead of us.
        let sunday = LocalDateTime(date: .literal(2026, 10, 4), time: .literal(23, 0))
        #expect(CourseSchedule.nextSession(of: chem, after: sunday) == LocalDateTime(date: .literal(2026, 10, 5), time: .literal(14)))
    }

    @Test func coursesWithoutSessionsComeLastInBothDirections() {
        var list = courses
        list[0].sessions = []   // bio
        let asc = CourseListQuery(sortBy: .nextSession).apply(to: list, context: context).map(\.id)
        let desc = CourseListQuery(sortBy: .nextSession, descending: true).apply(to: list, context: context).map(\.id)
        #expect(asc == ["chem", "econ", "math", "hist", "phil", "bio"])
        #expect(desc == ["phil", "hist", "math", "econ", "chem", "bio"])
        #expect(CourseSchedule.nextSession(of: list[0], after: now) == nil)
    }

    @Test func sortsByDueCountWithNameAsTieBreaker() {
        // math 3, bio 1, chem 1, others 0 (econ, hist, phil).
        #expect(ids(CourseListQuery(sortBy: .dueCount, descending: true)) == ["math", "chem", "bio", "phil", "hist", "econ"])
        #expect(ids(CourseListQuery(sortBy: .dueCount)) == ["econ", "hist", "phil", "bio", "chem", "math"])
    }

    @Test func filtersByFacultyIgnoringCaseAndAccents() {
        #expect(ids(CourseListQuery(faculties: ["sciences"])) == ["bio", "chem"])
        #expect(ids(CourseListQuery(faculties: ["SCIENCES", "mathemátics"])) == ["bio", "math", "chem"])
        // A course without a faculty (hist, phil) never matches a faculty filter.
        #expect(ids(CourseListQuery(faculties: ["Arts"])).isEmpty)
    }

    @Test func filtersBySearchTextInNameCodeAndProfessor() {
        #expect(ids(CourseListQuery(searchText: "  linear ")) == ["math"])
        #expect(ids(CourseListQuery(searchText: "chem 230")) == ["chem"])
        #expect(ids(CourseListQuery(searchText: "OKAFOR")) == ["bio"])
        #expect(ids(CourseListQuery(searchText: "dr.")) == ["bio", "math", "econ", "phil"])
        #expect(ids(CourseListQuery(searchText: "   ")) == ids(.default))
        #expect(ids(CourseListQuery(searchText: "zzz")).isEmpty)
    }

    @Test func filtersByHasDue() {
        #expect(ids(CourseListQuery(onlyWithDue: true)) == ["bio", "math", "chem"])
        #expect(CourseListQuery(onlyWithDue: true).apply(to: courses, context: .init(now: now)).isEmpty)
    }

    @Test func filtersCombineWithAnd() {
        let q = CourseListQuery(sortBy: .dueCount, descending: true, faculties: ["Sciences", "Mathematics"],
                                searchText: "a", onlyWithDue: true)
        // Sciences + Mathematics: bio, chem, math; with due: all three; "a" in name/code/professor: all.
        #expect(ids(q) == ["math", "chem", "bio"])
        #expect(ids(CourseListQuery(faculties: ["Sciences"], searchText: "cell", onlyWithDue: true)) == ["bio"])
        #expect(ids(CourseListQuery(faculties: ["Mathematics"], searchText: "cell")).isEmpty)
    }

    @Test func dueCountsCountOpenDatedTasksPerCourse() {
        let counts = CourseListQuery.dueCounts(from: world.dueItems)
        let expected = Dictionary(grouping: world.dueItems.filter { !$0.done && $0.due != nil }) { $0.source.courseID }
            .compactMapValues { $0.count }
        #expect(!counts.isEmpty)
        #expect(counts.count == expected.count)
        for (course, n) in counts { #expect(expected[course] == n, "\(course)") }
        var done = world.dueItems[0]; done.done = true
        #expect(CourseListQuery.dueCounts(from: [done]).isEmpty)
    }

    @Test func emptyInputAndCodable() throws {
        #expect(CourseListQuery.default.apply(to: [], context: context).isEmpty)
        let q = CourseListQuery(sortBy: .nextSession, descending: true, faculties: ["A"], searchText: "x", onlyWithDue: true)
        let data = try JSONEncoder().encode(q)
        #expect(try JSONDecoder().decode(CourseListQuery.self, from: data) == q)
    }
}
