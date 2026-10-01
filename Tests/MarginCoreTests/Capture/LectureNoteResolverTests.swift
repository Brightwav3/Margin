import Foundation
import Testing
@testable import MarginCore

/// M8-09.B: the nearest lecture of a course and inserting a line into its note.
/// Bio (Fixtures.week5): Tue and Thu 10:00-11:30. 28 Sep 2026 is a Monday. Lecture notes: 5 (15 Sep),
/// 6 (17 Sep), 7 (22 Sep), 8 (24 Sep), 9 (29 Sep, a Tuesday).
@Suite struct LectureNoteResolverTests {
    let world = Fixtures.week5
    var bio: Course { world.courses.first { $0.id == "bio" }! }
    var notes: [NoteSummary] { world.notes }

    private func resolver(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9) -> LectureNoteResolver {
        LectureNoteResolver(clock: FixedClock(local: LocalDateTime(date: .literal(2026, month, day), time: .literal(hour, minute))))
    }

    // MARK: Cancelled and moved classes

    /// Bio's classes of the week 28 Sep – 4 Oct, as `CourseCatalog.sessions(week:)` gives them.
    private func week(cancelTuesday: Bool = false, moveTuesdayTo moved: LocalDate? = nil) -> [SessionOccurrence] {
        bio.sessions.compactMap { s -> SessionOccurrence? in
            let date: LocalDate = s.day == .tuesday ? .literal(2026, 9, 29) : .literal(2026, 10, 1)
            if s.day == .tuesday, let moved { return SessionOccurrence(session: s, date: moved, originalDate: date) }
            return SessionOccurrence(session: s, date: date, isCancelled: s.day == .tuesday && cancelTuesday)
        }
    }

    @Test func occurrencesWithoutOverridesMatchTheSchedule() throws {
        let t = try #require(LectureNoteResolver(clock: FixedClock()).resolve(course: bio, notes: notes, occurrences: week()))
        #expect(t.date == .literal(2026, 9, 29) && t.noteID == "bio/lecture-9")
    }

    @Test func aCancelledLectureIsSkipped() throws {
        let t = try #require(LectureNoteResolver(clock: FixedClock()).resolve(course: bio, notes: notes, occurrences: week(cancelTuesday: true)))
        #expect(t.date == .literal(2026, 10, 1))
        #expect(t.noteID == nil && t.isUpcoming)
    }

    @Test func aMovedLectureCountsOnItsNewDay() throws {
        // Tuesday's lecture moved to Wednesday 30 Sep: on Wednesday at 9:00 it is the nearest one.
        let t = try #require(resolver(30, 9).resolve(course: bio, notes: notes, occurrences: week(moveTuesdayTo: .literal(2026, 9, 30))))
        #expect(t.date == .literal(2026, 9, 30) && t.isUpcoming)
    }

    @Test func otherCoursesClassesAreIgnored() throws {
        let other = week().map { o -> SessionOccurrence in
            var o = o
            o.session = Session(courseID: "math", day: o.session.day, start: o.session.start, lengthHours: 1.5, kind: "Lecture")
            return o
        }
        // Only another course's classes: no lecture in reach, so the nearest dated lecture note.
        let t = try #require(LectureNoteResolver(clock: FixedClock()).resolve(course: bio, notes: notes, occurrences: other))
        #expect(t.start == nil && t.noteID == "bio/lecture-9")
    }

    // MARK: Before, during and after a lecture

    @Test func mondayPicksTomorrowsLecture() throws {
        let t = try #require(LectureNoteResolver(clock: FixedClock()).resolve(course: bio, notes: notes))
        #expect(t.date == .literal(2026, 9, 29))
        #expect(t.start == .literal(10, 0))
        #expect(t.isUpcoming)
        #expect(t.noteID == "bio/lecture-9")       // the note of that day exists
    }

    @Test func minutesAroundTheLectureAllPickThatLecture() throws {
        // (hour, minute, upcoming)
        let times: [(Int, Int, Bool)] = [(9, 59, true), (10, 0, false), (10, 45, false), (11, 30, false), (11, 31, false), (14, 0, false)]
        for (h, m, upcoming) in times {
            let t = try #require(resolver(29, h, m).resolve(course: bio, notes: notes), "\(h):\(m)")
            #expect(t.date == .literal(2026, 9, 29), "\(h):\(m)")
            #expect(t.isUpcoming == upcoming, "\(h):\(m)")
            #expect(t.noteID == "bio/lecture-9")
        }
    }

    @Test func midnightsAroundALectureDay() throws {
        // Mon 23:59 and Tue 00:00 both look ahead to Tuesday 10:00.
        for (day, h, m) in [(28, 23, 59), (29, 0, 0)] {
            let t = try #require(resolver(day, h, m).resolve(course: bio, notes: notes))
            #expect(t.date == .literal(2026, 9, 29))
            #expect(t.isUpcoming)
        }
        // Tue 23:59 is 12.5 hours after the end; Thu is 34 hours away.
        let late = try #require(resolver(29, 23, 59).resolve(course: bio, notes: notes))
        #expect(late.date == .literal(2026, 9, 29))
        #expect(!late.isUpcoming)
    }

    @Test func betweenTwoLecturesTheNearerOneWinsAndATieGoesToThePast() throws {
        // Tue 11:30 end and Thu 10:00 start are 46.5 hours apart: the middle is Wed 10:45.
        let tie = try #require(resolver(30, 10, 45).resolve(course: bio, notes: notes))
        #expect(tie.date == .literal(2026, 9, 29))
        #expect(!tie.isUpcoming)
        let after = try #require(resolver(30, 10, 46).resolve(course: bio, notes: notes))
        #expect(after.date == .literal(2026, 10, 1))
        #expect(after.isUpcoming)
        #expect(after.noteID == nil)                       // no note of Thursday 1 Oct yet
        #expect(after.suggestedTitle == "Lecture 10")
    }

    // MARK: Weekend

    @Test func theWeekendSitsBetweenThursdayAndTuesday() throws {
        let friday = try #require(resolver(2, 16, month: 10).resolve(course: bio, notes: notes, semester: world.semester))
        #expect(friday.date == .literal(2026, 10, 1))
        // Thu 11:30 and Tue 10:00 are 118.5 hours apart: the middle is Saturday 22:45.
        let saturdayTie = try #require(resolver(3, 22, 45, month: 10).resolve(course: bio, notes: notes))
        #expect(saturdayTie.date == .literal(2026, 10, 1))
        #expect(!saturdayTie.isUpcoming)
        let saturdayNight = try #require(resolver(3, 22, 46, month: 10).resolve(course: bio, notes: notes))
        #expect(saturdayNight.date == .literal(2026, 10, 6))
        #expect(saturdayNight.isUpcoming)
        let sunday = try #require(resolver(4, 12, month: 10).resolve(course: bio, notes: notes))
        #expect(sunday.date == .literal(2026, 10, 6))
        let mondayMorning = try #require(resolver(5, 8, month: 10).resolve(course: bio, notes: notes))
        #expect(mondayMorning.date == .literal(2026, 10, 6))
    }

    // MARK: No lecture this week

    @Test func aBreakWeekLooksToTheNextWeek() throws {
        let week5 = try #require(world.semester.week(of: .literal(2026, 9, 29)))
        var semester = world.semester
        semester.breakWeeks = [week5]
        // Wed 30 Sep noon: Tue/Thu of this week are off; Thu 24 Sep ended 6 days ago, Tue 6 Oct is 5.9 days ahead.
        let t = try #require(resolver(30, 12).resolve(course: bio, notes: notes, semester: semester))
        #expect(t.date == .literal(2026, 10, 6))
        #expect(t.noteID == nil)
        // Two break weeks in a row: only the past lecture is within reach.
        semester.breakWeeks = [week5, week5 + 1]
        let past = try #require(resolver(30, 12).resolve(course: bio, notes: notes, semester: semester))
        #expect(past.date == .literal(2026, 9, 24))
        #expect(past.noteID == "bio/lecture-8")
    }

    @Test func nothingWithinAWeekFallsBackToTheNearestLectureNote() throws {
        let week5 = try #require(world.semester.week(of: .literal(2026, 9, 29)))
        var semester = world.semester
        semester.breakWeeks = [week5 - 1, week5, week5 + 1]
        let t = try #require(resolver(30, 12).resolve(course: bio, notes: notes, semester: semester))
        #expect(t.noteID == "bio/lecture-9")               // dated 29 Sep, one day away
        #expect(t.start == nil)
        #expect(t.date == .literal(2026, 9, 29))
        #expect(!t.isUpcoming)
    }

    @Test func aFinishedOrNotYetStartedSemesterHasNoScheduledLecture() throws {
        let over = Semester(id: "old", name: "Old", start: .literal(2026, 5, 1), end: .literal(2026, 9, 20))
        let t = try #require(resolver(29, 9).resolve(course: bio, notes: notes, semester: over))
        #expect(t.start == nil)
        #expect(t.noteID == "bio/lecture-9")
        let future = Semester(id: "next", name: "Next", start: .literal(2026, 10, 12), end: .literal(2027, 1, 30))
        #expect(resolver(29, 9).resolve(course: bio, notes: [], semester: future) == nil)
    }

    @Test func noLectureSessionsMeansNotesOnlyAndPastWinsATie() throws {
        var labOnly = bio
        labOnly.sessions = labOnly.sessions.map { var s = $0; s.kind = "Lab"; return s }
        let t = try #require(resolver(2, 12, month: 10).resolve(course: labOnly, notes: notes))
        #expect(t.noteID == "bio/lecture-9")               // 29 Sep is 3 days back, the nearest dated lecture note
        #expect(t.start == nil)

        let around = [
            NoteSummary(id: "bio/a", courseID: "bio", title: "A", kind: .lecture, date: .literal(2026, 10, 1)),
            NoteSummary(id: "bio/b", courseID: "bio", title: "B", kind: .lecture, date: .literal(2026, 9, 29)),
            NoteSummary(id: "bio/c", courseID: "bio", title: "C", kind: .study, date: .literal(2026, 9, 30)),      // not a lecture
            NoteSummary(id: "chem/d", courseID: "chem", title: "D", kind: .lecture, date: .literal(2026, 9, 30)), // other course
            NoteSummary(id: "bio/e", courseID: "bio", title: "E", kind: .lecture, date: nil),                    // undated
        ]
        let tie = try #require(resolver(30, 12).resolve(course: labOnly, notes: around))
        #expect(tie.noteID == "bio/b")
        #expect(!tie.isUpcoming)
        #expect(resolver(30, 12).resolve(course: labOnly, notes: []) == nil)
    }

    @Test func lectureKindIsMatchedIgnoringCase() throws {
        var course = bio
        course.sessions = course.sessions.map { var s = $0; s.kind = "LECTURE"; return s }
        #expect(try #require(resolver(29, 10).resolve(course: course, notes: notes)).start == .literal(10, 0))
    }

    @Test func twoLecturesOnOneDay() throws {
        var course = bio
        course.sessions = [
            Session(courseID: "bio", day: .tuesday, start: .literal(10), lengthHours: 1.5, kind: "Lecture"),
            Session(courseID: "bio", day: .tuesday, start: .literal(15), lengthHours: 1, kind: "Lecture"),
        ]
        let noon = try #require(resolver(29, 12).resolve(course: course, notes: []))
        #expect(noon.start == .literal(10, 0))
        let half = try #require(resolver(29, 13, 30).resolve(course: course, notes: []))
        #expect(half.start == .literal(15, 0))
        #expect(half.isUpcoming)
    }

    @Test func suggestedTitleFollowsTheHighestNumber() {
        #expect(LectureNoteResolver.suggestedTitle(courseNotes: []) == "Lecture 1")
        #expect(LectureNoteResolver.suggestedTitle(courseNotes: notes.filter { $0.courseID == "bio" }) == "Lecture 10")
        let odd = [NoteSummary(id: "x", title: "Lecture notes"), NoteSummary(id: "y", title: "lecture 3 — x")]
        #expect(LectureNoteResolver.suggestedTitle(courseNotes: odd) == "Lecture 4")
    }

    // MARK: Insert

    private func read(_ dir: TempDir, _ path: String) -> String? {
        dir.bytes(path).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func store(_ dir: TempDir) async throws -> VaultStore {
        try await VaultStore.open(root: dir.url, clock: FixedClock(), trash: PortableTrash(), createIfMissing: true)
    }

    @Test func insertLineAppendsAtTheEndAndKeepsEverythingElse() async throws {
        let dir = TempDir()
        let store = try await store(dir)
        let path = try VaultPath("Fall 2026/Cell Biology/Lecture 9.md")
        let original = "---\nid: n-abcd\ndate: 2026-09-29\n---\n# Lecture 9\n\nText without a final newline"
        try await store.create(path, content: original)
        let entry = try await LectureNoteResolver.insertLine("- [ ] Ask about osmosis ^t-x1y2", into: path, store: store)
        let text = try #require(read(dir, path.rawValue))
        #expect(text == original + "\n- [ ] Ask about osmosis ^t-x1y2\n")
        #expect(entry.kind == .modified)
        #expect(entry.path == path.rawValue)
        #expect(entry.beforeHash == ContentHash(of: original).hex)
        #expect(entry.afterHash == ContentHash(of: text).hex)
        // A second line follows directly.
        try await LectureNoteResolver.insertLine("Second\n", into: path, store: store)
        let again = try #require(read(dir, path.rawValue))
        #expect(again == text + "Second\n")
    }

    @Test func insertLineKeepsCRLF() async throws {
        let dir = TempDir()
        let store = try await store(dir)
        let path = try VaultPath("n.md")
        try await store.create(path, content: "# T\r\nline\r\n")
        try await LectureNoteResolver.insertLine("added", into: path, store: store)
        #expect(read(dir, "n.md") == "# T\r\nline\r\nadded\r\n")
    }

    @Test func insertLineRefusesEmptyLinesAndMissingFiles() async throws {
        let dir = TempDir()
        let store = try await store(dir)
        let path = try VaultPath("n.md")
        try await store.create(path, content: "# T\n")
        for empty in ["", "   ", "\n\n"] {
            do { _ = try await LectureNoteResolver.insertLine(empty, into: path, store: store); Issue.record("should throw") }
            catch let e as MarginError { #expect(e.code == "invalid") }
        }
        #expect(read(dir, "n.md") == "# T\n")
        do { _ = try await LectureNoteResolver.insertLine("x", into: try VaultPath("missing.md"), store: store); Issue.record("should throw") }
        catch let e as MarginError { #expect(e.code == "notFound") }
    }

    @Test func concurrentInsertsAllLandExactlyOnce() async throws {
        let dir = TempDir()
        let store = try await store(dir)
        let path = try VaultPath("n.md")
        try await store.create(path, content: "# Lecture\n")
        let count = 8
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask { try await LectureNoteResolver.insertLine("- line \(i)", into: path, store: store) }
            }
            try await group.waitForAll()
        }
        let text = try #require(read(dir, "n.md"))
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.first == "# Lecture")
        #expect(Set(lines.dropFirst()) == Set((0..<count).map { "- line \($0)" }))
        #expect(lines.count == count + 1)
    }
}
