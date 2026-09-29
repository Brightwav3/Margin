import Foundation
import Testing
@testable import MarginCore

/// One suite, run against `FixtureCourseCatalog` and `VaultCourseCatalog` (contract §5).
@Suite struct CourseCatalogConformanceTests {
    let world = Fixtures.week5

    @Test(arguments: HarnessKind.allCases)
    func coursesAreSortedByName(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let courses = try await h.courses.courses(query: nil)
            #expect(courses.map(\.id) == ["bio", "math", "econ", "hist", "chem", "phil"])
            #expect(courses.map(\.name) == ["Cell Biology", "Linear Algebra", "Macroeconomics", "Modern Europe",
                                            "Organic Chemistry", "Philosophy of Mind"])
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func everyCourseEqualsTheFixtureCourse(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            for expected in world.courses {
                let actual = try await h.courses.course(id: expected.id)
                #expect(actual == expected, "\(expected.id) differs")
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func queryMatchesNameCodeAndProfessorIgnoringCase(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let all: [CourseID] = ["bio", "math", "econ", "hist", "chem", "phil"]
            let cases: [(String?, [CourseID])] = [
                ("bio", ["bio"]), ("BIO 201", ["bio"]), ("OKAFOR", ["bio"]), ("dr.", ["bio", "math", "econ", "phil"]),
                ("  ", all), ("", all), (nil, all), ("nothing like this", []),
            ]
            for (query, expected) in cases {
                let ids = try await h.courses.courses(query: query).map(\.id)
                #expect(ids == expected, "query \(String(describing: query))")
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func unknownCourseIsNotFound(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            await #expect(throws: MarginError.self) { try await h.courses.course(id: "nope") }
            do { _ = try await h.courses.course(id: "nope") } catch let e as MarginError {
                #expect(e.code == "notFound")
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func semesterIsFall2026(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let semesters = try await h.courses.semesters()
            #expect(semesters == [world.semester])
            #expect(h.clock.weekOfSemester(world.semester) == 5)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func sessionsOfWeek5MatchTheTimetable(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let week = try await h.courses.sessions(week: 5)
            #expect(week.count == 11)
            // Same order as the fixture timetable (by day, then start), placed on 28 Sep – 2 Oct.
            let monday = LocalDate.literal(2026, 9, 28)
            let expected = world.sessions.map { SessionOccurrence(session: $0, date: monday.adding(days: $0.day.isoNumber - 1)) }
            #expect(week == expected)
            #expect(week.first?.date == monday && week.first?.session.courseID == "math")
            #expect(week.last?.date == LocalDate.literal(2026, 10, 2))
            // Other weeks have the same classes on other dates.
            let first = try await h.courses.sessions(week: 1)
            #expect(first.count == 11 && first.first?.date == .literal(2026, 8, 31))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func weeksOutsideTheSemesterAreInvalid(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            for week in [0, -1, world.semester.weekCount + 1] {
                do {
                    _ = try await h.courses.sessions(week: week)
                    Issue.record("week \(week) should throw")
                } catch let e as MarginError { #expect(e.code == "invalid", "week \(week): \(e)") }
            }
            let last = try await h.courses.sessions(week: world.semester.weekCount)
            #expect(last.count == 11)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func updatesAreDeliveredWhenACourseChangesBehindTheApp(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let updates = h.courses.updates            // subscribe first
            try await h.editCourseRoom("bio", "Sci 999")
            let update = await next(from: updates) { $0.courses.contains("bio") }
            #expect(update?.courses == ["bio"])
            let bio = try await h.courses.course(id: "bio")
            #expect(bio.room == "Sci 999")
            // Other courses are untouched.
            let chem = try await h.courses.course(id: "chem")
            #expect(chem == world.course("chem"))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func everySubscriberGetsTheUpdate(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let a = h.courses.updates, b = h.courses.updates
            try await h.editCourseRoom("math", "Math 202")
            async let first = next(from: a) { $0.courses == ["math"] }
            async let second = next(from: b) { $0.courses == ["math"] }
            #expect(await first != nil)
            #expect(await second != nil)
        }
    }
}
