import Testing
@testable import MarginCore

@Suite struct GradeCalculatorTests {
    static let parts = [GradingPart(label: "Homework", weightPercent: 40), GradingPart(label: "Exam", weightPercent: 60)]

    static func g(_ id: String, _ group: String?, _ score: Double?, _ max: Double?, course: CourseID = "c") -> Grade {
        Grade(id: id, courseID: course, item: id, group: group, score: score, max: max)
    }

    static func course(_ id: CourseID, credits: Int?, parts: [GradingPart] = GradeCalculatorTests.parts) -> Course {
        Course(id: id, semester: "s", name: id, code: id, credits: credits,
               style: CourseStyle(icon: "x", color: "#000", background: "#fff", foreground: "#000", dot: "#000"),
               grading: parts)
    }

    @Test func weightedAverageOverAllGroups() {
        let r = GradeCalculator.course(id: "c", grading: Self.parts, grades: [
            Self.g("h1", "Homework", 80, 100), Self.g("e1", "Exam", 90, 100)])
        #expect(abs((r.percent ?? 0) - 86) < 1e-9)
        #expect(r.letter == "B")
        #expect(r.gradedWeightPercent == 100)
    }

    @Test func missingGroupIsRenormalised() {
        let r = GradeCalculator.course(id: "c", grading: Self.parts, grades: [Self.g("h1", "Homework", 45, 50)])
        #expect(abs((r.percent ?? 0) - 90) < 1e-9)
        #expect(r.gradedWeightPercent == 40)
        #expect(r.groups[1].percent == nil)
    }

    @Test func pointsBasedInsideGroup() {
        let r = GradeCalculator.course(id: "c", grading: Self.parts, grades: [
            Self.g("h1", "Homework", 10, 10), Self.g("h2", "Homework", 0, 90)])
        #expect(abs((r.percent ?? 0) - 10) < 1e-9)
        #expect(r.letter == "F")
    }

    @Test func pendingItemsAndInvalidMaxAreSkipped() {
        let r = GradeCalculator.course(id: "c", grading: Self.parts, grades: [
            Self.g("h1", "Homework", 8, 10), Self.g("h2", "Homework", nil, 10), Self.g("h3", "Homework", 5, 0)])
        #expect(abs((r.percent ?? 0) - 80) < 1e-9)
        #expect(r.groups[0].gradedCount == 1)
        #expect(r.groups[0].totalCount == 3)
    }

    @Test func unknownGroupAndUngroupedAreIgnoredAndListed() {
        let r = GradeCalculator.course(id: "c", grading: Self.parts, grades: [
            Self.g("h1", " homework ", 7, 10), Self.g("x", "Bonus", 10, 10), Self.g("y", nil, 10, 10)])
        #expect(abs((r.percent ?? 0) - 70) < 1e-9)
        #expect(r.ignoredItemIDs == ["x", "y"])
    }

    @Test func noGradesGivesNil() {
        let r = GradeCalculator.course(id: "c", grading: Self.parts, grades: [Self.g("h", "Homework", nil, nil)])
        #expect(r.percent == nil && r.letter == nil && r.summary == nil)
    }

    @Test func noGradingPartsUsesAllItems() {
        let r = GradeCalculator.course(id: "c", grading: [], grades: [Self.g("a", nil, 30, 40), Self.g("b", "Any", 10, 10)])
        #expect(abs((r.percent ?? 0) - 80) < 1e-9)
    }

    @Test func scaleThresholds() {
        let us: [(Double, String)] = [(100, "A"), (93, "A"), (92.99, "A−"), (90, "A−"), (87, "B+"), (83, "B"),
                                      (80, "B−"), (60, "D−"), (59.9, "F"), (0, "F")]
        for (p, l) in us { #expect(GradeScale.us.letter(for: p) == l) }
        let cz: [(Double, String)] = [(95, "A"), (89.9, "B"), (70, "C"), (60, "D"), (50, "E"), (49.99, "F")]
        for (p, l) in cz { #expect(GradeScale.czech.letter(for: p) == l) }
    }

    @Test func semesterAverageWeightedByCredits() {
        let a = Self.course("a", credits: 6), b = Self.course("b", credits: 2), c = Self.course("c", credits: 5)
        let grades = [Self.g("a1", "Homework", 100, 100, course: "a"), Self.g("b1", "Homework", 60, 100, course: "b")]
        let r = GradeCalculator.semester(courses: [a, b, c], grades: grades)
        #expect(abs((r.percent ?? 0) - 90) < 1e-9)   // (100*6 + 60*2) / 8; course c has no grades
        #expect(r.letter == "A−")
        #expect(r.courses.count == 3)
        #expect(GradeCalculator.semester(courses: [c], grades: []).percent == nil)
    }

    @Test func fixturesWeek5BioCourse() throws {
        let world = Fixtures.week5
        let bio = try #require(world.course("bio"))
        let r = GradeCalculator.course(bio, grades: world.grades)
        // Problem sets 37/40 = 92.5 (weight 20), Lab reports 88 (weight 25): (1850 + 2200) / 45 = 90.
        #expect(abs((r.percent ?? 0) - 90) < 1e-9)
        #expect(r.letter == "A−")
        #expect(r.gradedWeightPercent == 45)
        #expect(r.summary == GradeSummary(courseID: "bio", letter: "A−", percent: 90))
        #expect(r.ignoredItemIDs.isEmpty)
    }
}
