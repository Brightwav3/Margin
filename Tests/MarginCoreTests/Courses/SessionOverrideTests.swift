import Foundation
import Testing
@testable import MarginCore

/// M10-14.B: changing the time or room of one class, or cancelling it, is stored in `_course.md`
/// (`overrides:`), survives a restart and shows in the timetable and on the course.
@Suite struct SessionOverrideTests {
    private let monday = LocalDate.literal(2026, 9, 28)
    private let bioFile = "Fall 2026/Cell Biology/_course.md"

    private func cancel(_ session: String, _ course: CourseID, on date: LocalDate, note: String? = nil) -> SessionOverride {
        SessionOverride(sessionID: session, courseID: course, originalDate: date, cancelled: true, note: note)
    }

    private func read(_ v: CourseVault, _ path: String) -> (overrides: [SessionOverride], unreadable: [FrontmatterValue]) {
        let fm = Frontmatter.parse(v.text(path)).frontmatter
        return fm.map { SessionOverrideCodec.read($0, courseID: "bio") } ?? ([], [])
    }

    @Test func aCancelledClassIsWrittenAsOneListEntryAndSurvivesARestart() async throws {
        let v = try await CourseVault.open()
        let before = v.text(bioFile)
        let cs = try await v.writer.override(session: cancel("bio-tue-1000", "bio", on: monday.adding(days: 1), note: "Professor ill"),
                                             actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        let after = v.text(bioFile)
        #expect(cs.entries.count == 1 && cs.entries[0].afterHash == ContentHash(of: after).hex)
        // Only the new key was added; everything before it is byte-identical.
        let added = after.components(separatedBy: "\n").filter { !before.components(separatedBy: "\n").contains($0) }
        #expect(added == ["overrides:", "  - {session: bio-tue-1000, date: 2026-09-29, cancelled: true, note: Professor ill}"], "\(added)")
        #expect(after.hasPrefix(String(before.prefix(upTo: try #require(before.range(of: "\n---\n", range: before.index(before.startIndex, offsetBy: 4)..<before.endIndex)).lowerBound))))
        #expect(CourseValidator.validate(after).isEmpty)
        await v.shutdown()

        let again = try await CourseVault.reopen(v.dir)
        let week = try await again.catalog.sessions(week: 5)
        let cancelled = week.filter(\.isCancelled)
        #expect(cancelled.map(\.id) == ["bio-tue-1000@2026-09-29"] && cancelled[0].note == "Professor ill")
        #expect(week.count == 11)
        await again.shutdown()
    }

    @Test func aMovedClassKeepsItsIdentityAndShowsAtTheNewTime() async throws {
        let v = try await CourseVault.open()
        let thursday = monday.adding(days: 3)
        let to = LocalDateTime(date: monday.adding(days: 4), time: .literal(14, 30))
        _ = try await v.writer.override(
            session: SessionOverride(sessionID: "bio-thu-1000", courseID: "bio", originalDate: thursday, newStart: to, newRoom: "Sci 300, annex", note: "Lab is busy"),
            actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(read(v, bioFile).overrides.count == 1)
        await v.shutdown()

        let again = try await CourseVault.reopen(v.dir)
        let occurrence = try #require(try await again.catalog.sessions(week: 5).first { $0.session.id == "bio-thu-1000" })
        #expect(occurrence.date == to.date && occurrence.originalDate == thursday && occurrence.session.start == to.time)
        #expect(occurrence.session.room == "Sci 300, annex" && occurrence.note == "Lab is busy" && !occurrence.isCancelled)
        #expect(occurrence.session.lengthHours == 1.5 && occurrence.session.kind == "Lecture")
        // The weekly session itself is untouched.
        let course = try await again.catalog.course(id: "bio")
        #expect(course.sessions.first { $0.id == "bio-thu-1000" }?.start == .literal(10, 0))
        await again.shutdown()
    }

    @Test func anOverrideReplacesTheEarlierOneAndClearingRestoresTheFile() async throws {
        let v = try await CourseVault.open()
        let original = v.text(bioFile)
        let day = monday.adding(days: 1)
        _ = try await v.writer.override(session: cancel("bio-tue-1000", "bio", on: day), actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        // Same session and day again: replaced, not added.
        _ = try await v.writer.override(
            session: SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: day, newRoom: "Hall Z"),
            actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        _ = try await v.writer.override(session: cancel("bio-tue-1000", "bio", on: day.adding(days: 7)), actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        let stored = read(v, bioFile).overrides
        #expect(stored.map(\.id) == ["bio-tue-1000@2026-09-29", "bio-tue-1000@2026-10-06"])
        #expect(stored[0].newRoom == "Hall Z" && !stored[0].cancelled)
        // The same override again writes nothing.
        let same = try await v.writer.override(session: cancel("bio-tue-1000", "bio", on: day.adding(days: 7)), actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(same.isEmpty)

        for date in [day, day.adding(days: 7)] {
            _ = try await v.writer.clearOverride(sessionID: "bio-tue-1000", course: "bio", originalDate: date, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        }
        #expect(v.text(bioFile) == original)                                   // the key is gone again, nothing else changed
        await v.shutdown()
    }

    @Test func entriesTheAppCannotReadAreKept() async throws {
        let dir = TempDir()
        try dir.seed("Fall 2026/Odd/_course.md", Data("""
            ---
            name: Odd
            sessions:
              - {day: Tue, time: "10:00", length: 1.5, kind: Lecture}
            overrides:
              - {session: odd-tue-1000, date: 2026-09-29, room: A1}
              - {who: knows, what: this is}
            ---
            Body
            """.utf8))
        try dir.seed(".margin/semesters.json", Data(SampleVaultGenerator.semestersJSON(Fixtures.week5.semester).utf8))
        let v = try await CourseVault.reopen(dir)
        _ = try await v.writer.override(session: cancel("odd-tue-1000", "odd", on: LocalDate.literal(2026, 10, 6)), actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        let text = v.text("Fall 2026/Odd/_course.md")
        #expect(text.contains("{who: knows, what: this is}") && text.hasSuffix("Body"))
        #expect(text.contains("session: odd-tue-1000, date: 2026-09-29, room: A1") && text.contains("date: 2026-10-06, cancelled: true"))
        await v.shutdown()
    }

    @Test func aDryRunWritesNothingAndTheCatalogAnnouncesTheChange() async throws {
        let v = try await CourseVault.open()
        let before = v.dir.snapshot()
        let dry = try await v.writer.override(session: cancel("bio-tue-1000", "bio", on: monday.adding(days: 1)), actor: .user, baseVersion: nil, dryRun: true, idempotencyKey: nil)
        #expect(dry.isDryRun && dry.entries.count == 1)
        #expect(v.dir.snapshot() == before)

        let updates = v.catalog.updates
        _ = try await v.writer.override(session: cancel("bio-tue-1000", "bio", on: monday.adding(days: 1)), actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        var seen: CatalogUpdate?
        for await update in updates { seen = update; break }
        #expect(seen?.courses == ["bio"])
        await v.shutdown()
    }

    @Test func editingOverridesByHandInAnotherProgramShowsUp() async throws {
        let v = try await CourseVault.open()
        let updates = v.catalog.updates
        var text = v.text(bioFile)
        text = text.replacingOccurrences(of: "\n---\n", with: "\noverrides:\n  - {session: bio-tue-1000, date: 2026-09-29, cancelled: true}\n---\n")
        try v.dir.seed(bioFile, Data(text.utf8))
        var seen: CatalogUpdate?
        for await update in updates where update.courses.contains("bio") { seen = update; break }
        #expect(seen != nil)
        let week = try await v.catalog.sessions(week: 5)
        #expect(week.filter(\.isCancelled).map(\.id) == ["bio-tue-1000@2026-09-29"])
        await v.shutdown()
    }

    @Test func theCodecReadsWhatItWritesAndIgnoresIncompleteEntries() throws {
        let overrides = [
            SessionOverride(sessionID: "a-mon-0900", courseID: "a", originalDate: .literal(2026, 9, 28), cancelled: true, note: "x: y, #z"),
            SessionOverride(sessionID: "a-mon-0900", courseID: "a", originalDate: .literal(2026, 10, 5),
                            newStart: LocalDateTime(date: .literal(2026, 10, 6), time: .literal(8, 5)), newRoom: "true", note: nil),
            SessionOverride(sessionID: "a-mon-0900", courseID: "a", originalDate: .literal(2026, 10, 12), newRoom: "  Room 3 "),
        ]
        var fm = try #require(Frontmatter.parse("---\nname: A\n---\n").frontmatter)
        SessionOverrideCodec.write(overrides, unreadable: [], to: &fm)
        let reparsed = try #require(Frontmatter.parse(fm.render()).frontmatter)
        let (back, unreadable) = SessionOverrideCodec.read(reparsed, courseID: "a")
        #expect(back == overrides && unreadable.isEmpty)

        let incomplete: [FrontmatterValue] = [
            .map([.init("session", "a-mon-0900")]), .map([.init("date", .date(.literal(2026, 9, 28))), .init("cancelled", true)]),
            .map([.init("session", "a-mon-0900"), .init("date", .date(.literal(2026, 9, 28)))]),          // changes nothing
            .map([.init("session", "a-mon-0900"), .init("date", "not a date"), .init("room", "x")]),
            .string("nope"),
        ]
        for item in incomplete { #expect(SessionOverrideCodec.decode(item, courseID: "a") == nil, "\(item)") }
        #expect(CourseValidator.validate("---\nname: A\noverrides:\n  - {session: x}\n---\n").contains { $0.message.contains("overrides:") && $0.message.contains("session: x") })
    }

    @Test func theTimetableAppliesOverridesAcrossWeeks() throws {
        let semester = Fixtures.week5.semester
        let bio = try #require(Fixtures.week5.course("bio"))
        let tuesday = monday.adding(days: 1)
        func week(_ n: Int, _ overrides: [SessionOverride]) throws -> [SessionOccurrence] {
            try ServiceRules.occurrences(week: n, semester: semester, courses: [bio], overrides: overrides)
        }
        // A class moved to the previous week appears there, not in its own.
        let earlier = SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday,
                                      newStart: LocalDateTime(date: monday.adding(days: -2), time: .literal(9)))
        #expect(try week(4, [earlier]).contains { $0.id == "bio-tue-1000@2026-09-29" && $0.date == monday.adding(days: -2) })
        #expect(try week(5, [earlier]).map(\.id) == ["bio-thu-1000@2026-10-01"])
        // Cancelling and moving on the same day: the cancel wins, the new time is ignored.
        let both = SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday, cancelled: true,
                                   newStart: LocalDateTime(date: tuesday, time: .literal(15)), newRoom: "X")
        let cancelled = try #require(try week(5, [both]).first { $0.session.id == "bio-tue-1000" })
        #expect(cancelled.isCancelled && cancelled.session.start == .literal(10, 0) && cancelled.date == tuesday)
        // An override of another course or another day changes nothing.
        let other = SessionOverride(sessionID: "bio-tue-1000", courseID: "chem", originalDate: tuesday, cancelled: true)
        let otherDay = SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday.adding(days: 7), cancelled: true)
        #expect(try week(5, [other, otherDay]) == week(5, []))
        // Sorted by the effective day and time.
        let late = SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday, newStart: LocalDateTime(date: tuesday.adding(days: 2), time: .literal(8)))
        #expect(try week(5, [late]).map(\.date) == [monday.adding(days: 3), monday.adding(days: 3)])
        #expect(try week(5, [late]).map(\.session.start) == [.literal(8, 0), .literal(10, 0)])
    }
}
