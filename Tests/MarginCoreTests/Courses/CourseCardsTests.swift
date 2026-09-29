import Foundation
import Testing
@testable import MarginCore

/// M4-08: cards of the course gallery (mockup 2c) generated from the timetable.
/// Fixture clock: Monday 28 Sep 2026, 13:24, week 5 of Fall 2026 (week 1 starts Mon 31 Aug).
@Suite struct CourseCardsTests {
    let world = Fixtures.week5
    let now = LocalDateTime(date: .literal(2026, 9, 28), time: .literal(13, 24))
    var bio: Course { world.courses.first { $0.id == "bio" }! }

    private func cards(_ course: Course? = nil, notes: [NoteSummary]? = nil, semester: Semester? = nil,
                       lookahead: Int = 1, includePast: Bool = true) -> [CourseCard] {
        CourseCardBuilder.cards(course: course ?? bio, semester: semester ?? world.semester,
                                notes: notes ?? world.notes, now: now, lookaheadDays: lookahead,
                                includePastWithoutNote: includePast)
    }

    // MARK: The acceptance test

    @Test func cardForLecture9IsCreatedFromASession() throws {
        // Tuesday 10:00, 1.5 h, room Sci 204: the session of the timetable behind Lecture 9.
        let session = Session(courseID: "bio", day: .tuesday, start: .literal(10), lengthHours: 1.5,
                              kind: "Lecture", room: "Sci 204")
        let occurrence = SessionOccurrence(session: session, date: .literal(2026, 9, 29))
        let card = CourseCardBuilder.card(for: occurrence, ordinal: 9, note: nil, now: now)

        #expect(card.label == "Lecture 9" && card.kind == "Lecture" && card.ordinal == 9)
        #expect(card.date == .literal(2026, 9, 29) && card.start == .literal(10) && card.room == "Sci 204")
        #expect(card.isNotStarted && card.note.isPlaceholder && card.isUpcoming && card.fromSchedule)
        #expect(card.theme == nil)
        #expect(card.id == "bio-tue-1000@2026-09-29")
        // The placeholder note is what NoteRepository.create would make.
        #expect(card.note.id == "bio/lecture-9" && card.note.title == "Lecture 9" && card.note.kind == .lecture)
        #expect(card.note.date == .literal(2026, 9, 29) && card.note.courseID == "bio")
        #expect(card.note.snippet == "Not started. Created from your timetable at 10:00.")
    }

    @Test func lecture9ComesOutOfTheTimetableOfTheFullCourse() throws {
        // No notes at all: every class is a Not started card and Tue 29 Sep is Lecture 9.
        let all = cards(notes: [])
        let l9 = try #require(all.first)
        #expect(l9.label == "Lecture 9" && l9.date == .literal(2026, 9, 29) && l9.isNotStarted)
        #expect(all.allSatisfy { $0.isNotStarted && $0.fromSchedule })
        let expectedLabels: [String] = (1...9).reversed().map { "Lecture \($0)" }
        #expect(all.map(\.label) == expectedLabels)
    }

    // MARK: The gallery of the mockup

    @Test func galleryOfTheMockupInOrder() throws {
        let all = cards()
        // Mockup 2c shows Lecture 9, 8, 7, Lab 2, Lecture 6, 5; older classes follow.
        #expect(all.prefix(6).map(\.label) == ["Lecture 9", "Lecture 8", "Lecture 7", "Lab 2", "Lecture 6", "Lecture 5"])
        let days: [LocalDate] = [.literal(2026, 9, 29), .literal(2026, 9, 24), .literal(2026, 9, 22),
                                 .literal(2026, 9, 21), .literal(2026, 9, 17), .literal(2026, 9, 15)]
        let firstSix: [LocalDate] = all.prefix(6).map(\.date)
        #expect(firstSix == days)
        #expect(all.dropFirst(6).map(\.label) == ["Lecture 4", "Lecture 3", "Lecture 2", "Lecture 1"])
        #expect(all.dropFirst(6).allSatisfy { $0.isNotStarted })

        let l9 = all[0], l8 = all[1], lab = all[3]
        #expect(l9.isNotStarted && l9.note.id == "bio/lecture-9" && l9.theme == "Membrane transport" && l9.isUpcoming)
        #expect(l9.note.snippet.hasPrefix("Not started. Created from your timetable at 10:00"))
        #expect(!l8.isNotStarted && l8.theme == "Cell membrane" && !l8.isUpcoming && l8.note.wordCount == 412)
        // Lab 2 has no class in the timetable of Cell Biology: an extra card from its note.
        #expect(!lab.fromSchedule && lab.ordinal == nil && lab.start == nil && lab.kind == "Lab" && lab.theme == "Microscopy")
        #expect(lab.note.imageCount == 3)
        // Every note is used once.
        #expect(Set(all.map(\.note.id)).count == all.count)
        // Study notes and assignments are not classes.
        #expect(!all.contains { $0.note.id == "bio/glossary" || $0.note.id == "bio/assignments" })
    }

    @Test func withoutPastEmptyClassesTheGalleryIsExactlyTheMockup() {
        let all = cards(includePast: false)
        #expect(all.map(\.label) == ["Lecture 9", "Lecture 8", "Lecture 7", "Lab 2", "Lecture 6", "Lecture 5"])
    }

    // MARK: Horizon

    @Test func lookaheadReachesIntoTheWeek() {
        #expect(cards(lookahead: 0).first?.label == "Lecture 8")    // horizon Mon 28: Tue 29 is beyond
        #expect(cards(lookahead: 1).first?.label == "Lecture 9")
        let week = cards(lookahead: 7)
        #expect(week.prefix(2).map(\.label) == ["Lecture 10", "Lecture 9"])   // Thu 1 Oct; Tue 6 Oct is beyond Mon 5 Oct
        let l10 = week[0]
        #expect(l10.isNotStarted && l10.note.id == "bio/lecture-10" && l10.date == .literal(2026, 10, 1) && l10.isUpcoming)
        #expect(cards(lookahead: -5) == cards(lookahead: 0))
    }

    @Test func numberingDoesNotDependOnTheLookahead() {
        let short = cards(notes: [], lookahead: 1), long = cards(notes: [], lookahead: 30)
        for card in short { #expect(long.first { $0.id == card.id }?.label == card.label) }
        #expect(long.count > short.count)
    }

    // MARK: Numbering per kind, breaks and term bounds

    @Test func classesAreNumberedPerKind() throws {
        let chem = world.courses.first { $0.id == "chem" }!   // Mon 14:00 Lab, Fri 13:00 Lecture
        let all = cards(chem, notes: [], lookahead: 7)
        #expect(all.first?.label == "Lab 6")        // labs on 31 Aug, 7, 14, 21, 28 Sep are 1...5; Mon 5 Oct is within 7 days
        let byLabel = Dictionary(uniqueKeysWithValues: all.map { ($0.label, $0) })
        #expect(byLabel["Lab 5"]?.date == .literal(2026, 9, 28))
        #expect(byLabel["Lecture 5"]?.date == .literal(2026, 10, 2))
        #expect(byLabel["Lecture 1"]?.date == .literal(2026, 9, 4))
    }

    @Test func breakWeeksHaveNoClasses() {
        var semester = world.semester
        semester.breakWeeks = [2]   // Sep 7-13: no Tue 8 / Thu 10 lectures
        let all = cards(notes: [], semester: semester)
        #expect(!all.contains { $0.date == .literal(2026, 9, 8) || $0.date == .literal(2026, 9, 10) })
        #expect(all.first?.label == "Lecture 7")   // Tue 29 Sep is now the 7th
    }

    @Test func classesOutsideTheTermAreLeftOut() {
        let semester = Semester(id: "fall-2026", name: "Fall 2026", start: .literal(2026, 9, 2), end: .literal(2026, 9, 24))
        // Term starts Wed 2 Sep and ends Thu 24 Sep: first lecture Thu 3 Sep, last Thu 24 Sep.
        let all = cards(notes: [], semester: semester, lookahead: 60)
        #expect(all.first?.date == .literal(2026, 9, 24))
        #expect(all.last?.date == .literal(2026, 9, 3))
        #expect(all.last?.label == "Lecture 1")
    }

    // MARK: Matching notes

    @Test func aNoteMatchesByDateAndKindOrByLabelWhenUndated() {
        let dated = NoteSummary(id: "bio/x", courseID: "bio", title: "Whatever", kind: .lecture, date: .literal(2026, 9, 29), wordCount: 3)
        let wrongKind = NoteSummary(id: "bio/y", courseID: "bio", title: "Lecture 8", kind: .study, date: .literal(2026, 9, 24))
        let undated = NoteSummary(id: "bio/z", courseID: "bio", title: "Lecture 7 — Draft", kind: .lecture)
        let otherCourse = NoteSummary(id: "chem/c", courseID: "chem", title: "Lecture 9", kind: .lecture, date: .literal(2026, 9, 29))
        let all = cards(notes: [dated, wrongKind, undated, otherCourse])
        let byLabel = Dictionary(uniqueKeysWithValues: all.filter(\.fromSchedule).map { ($0.label, $0) })
        #expect(byLabel["Lecture 9"]?.note.id == "bio/x")
        #expect(byLabel["Lecture 9"]?.theme == "Whatever")
        #expect(byLabel["Lecture 9"]?.isNotStarted == false)
        #expect(byLabel["Lecture 7"]?.note.id == "bio/z")
        #expect(byLabel["Lecture 8"]?.isNotStarted == true)   // a study note is not the lecture note
        #expect(!all.contains { $0.note.id == "chem/c" })
    }

    @Test func twoClassesOnOneDayGetOneNoteEach() {
        var course = bio
        course.sessions = [Session(courseID: "bio", day: .tuesday, start: .literal(10), lengthHours: 1, kind: "Lecture"),
                           Session(courseID: "bio", day: .tuesday, start: .literal(14), lengthHours: 1, kind: "Lecture")]
        let note = NoteSummary(id: "bio/only", courseID: "bio", title: "Extra lecture", kind: .lecture, date: .literal(2026, 9, 29))
        let all = cards(course, notes: [note])
        let onTuesday = all.filter { $0.date == .literal(2026, 9, 29) }
        #expect(onTuesday.count == 2)
        #expect(onTuesday.filter { !$0.isNotStarted }.count == 1)
        #expect(onTuesday.map(\.label) == ["Lecture 10", "Lecture 9"])   // newest (14:00) first
    }

    @Test func aCourseWithoutSessionsHasOnlyItsClassNotes() {
        var course = bio
        course.sessions = []
        let all = cards(course)
        let expected = ["Lecture 9", "Lecture 8", "Lecture 7", "Lab 2", "Lecture 6", "Lecture 5"]
        #expect(all.map(\.label) == expected)
        #expect(all.allSatisfy { !$0.fromSchedule })
    }

    // MARK: Through the services

    @Test func fixtureServicesGiveTheSameGallery() async throws {
        let env = AppEnvironment.fixture()
        let viaServices = try await CourseCardBuilder.cards(courseID: "bio", catalog: env.courses, notes: env.notes,
                                                            clock: env.clock, lookaheadDays: 1)
        #expect(viaServices == cards())
        do { _ = try await CourseCardBuilder.cards(courseID: "nope", catalog: env.courses, notes: env.notes, clock: env.clock) }
        catch let e as MarginError { #expect(e.code == "notFound") }
        await env.shutdown()
    }

    @Test func vaultServicesGiveTheSameClassesAndNotes() async throws {
        let dir = TempDir()
        let clock = FixedClock()
        let store = try await VaultStore.open(root: dir.url, clock: clock)
        try await SampleVaultGenerator.generate(into: store, from: world)
        let env = try await AppEnvironment.vault(at: dir.url, clock: clock)
        let viaVault = try await CourseCardBuilder.cards(courseID: "bio", catalog: env.courses, notes: env.notes,
                                                         clock: env.clock, lookaheadDays: 1)
        let expected = cards()
        #expect(viaVault.map(\.label) == expected.map(\.label))
        #expect(viaVault.map(\.date) == expected.map(\.date))
        #expect(viaVault.map(\.theme) == expected.map(\.theme))
        #expect(viaVault.map(\.note.id) == expected.map(\.note.id))
        // Known difference: the vault format has no placeholder marker yet (see NoteRecord.summary), so
        // Lecture 9's note file counts as started there; the classes without a file are Not started in both.
        let vaultFlags: [Bool] = viaVault.map(\.isNotStarted), fixtureFlags: [Bool] = expected.map(\.isNotStarted)
        #expect(Array(vaultFlags.dropFirst()) == Array(fixtureFlags.dropFirst()))
        await env.shutdown()
    }
}
