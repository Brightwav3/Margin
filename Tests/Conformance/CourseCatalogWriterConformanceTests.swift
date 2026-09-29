import Foundation
import Testing
@testable import MarginCore

// Which implementations each group of tests runs against. The vault implementation arrives task by
// task (M10-16.B create, M10-12.B rename/style, M10-13.B archive, M10-14.B overrides); a group is
// widened to `HarnessKind.allCases` in the commit that implements it.
private let createKinds = HarnessKind.allCases
private let editKinds = HarnessKind.allCases
private let archiveKinds = HarnessKind.allCases
private let overrideKinds: [HarnessKind] = [.fixture]

private func codeOf<T>(_ body: () async throws -> T) async -> String? {
    do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other" }
}

private let stats = NewCourse(name: "Statistics", semester: "fall-2026", code: "STA 101", professor: "Dr. Novak", room: "Hall C")

/// `CourseCatalogWriter`, run against `FixtureCourseCatalogWriter` and `VaultCourseCatalogWriter`
/// (contract §5).
@Suite struct CourseCatalogWriterConformanceTests {
    // MARK: create (M10-16.B)

    @Test(arguments: createKinds)
    func createAddsACourseWithTheDefaultSchedule(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let updates = h.courses.updates
            let cs = try await h.writer.create(stats, actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .created)
            #expect(cs.entries[0].path == "Fall 2026/Statistics/_course.md" && cs.actor == testActor)
            let course = try await h.courses.course(id: "statistics")
            #expect(course.name == "Statistics" && course.code == "STA 101" && course.professor == "Dr. Novak")
            #expect(course.semester == "fall-2026" && course.style.icon == "school")
            #expect(course.sessions.count == 1)
            #expect(course.sessions[0].day == .monday && course.sessions[0].start == .literal(10, 0)
                    && course.sessions[0].lengthHours == 1.5 && course.sessions[0].kind == "Lecture")
            // It is part of the catalog and of the timetable.
            let names = try await h.courses.courses(query: nil).map(\.name)
            #expect(names.count == 7 && names.contains("Statistics"))
            #expect(try await h.courses.sessions(week: 5).count == 12)
            #expect(await next(from: updates, where: { $0.courses.contains("statistics") }) != nil)
            // The version is the hash written.
            #expect(try await h.writer.courseVersion(id: "statistics") == cs.entries[0].afterHash)
        }
    }

    @Test(arguments: createKinds)
    func createTakesGivenSessionsAndStyle(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            var new = stats
            new.icon = "calculate"; new.color = "math"; new.credits = 4
            new.sessions = [NewSession(day: .tuesday, start: .literal(9, 30), lengthHours: 2, kind: "Lab", room: "Lab 2"),
                            NewSession(day: .thursday, start: .literal(9, 30))]
            _ = try await h.writer.create(new, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let course = try await h.courses.course(id: "statistics")
            #expect(course.style.icon == "calculate" && course.style.color == "math" && course.credits == 4)
            #expect(course.sessions.map(\.id) == ["statistics-tue-0930", "statistics-thu-0930"])
            #expect(course.sessions[0].room == "Lab 2" && course.sessions[1].room == "Hall C")
        }
    }

    @Test(arguments: createKinds)
    func createHonoursDryRunAndIdempotency(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let dry = try await h.writer.create(stats, actor: testActor, baseVersion: nil, dryRun: true, idempotencyKey: "k")
            #expect(dry.isDryRun && dry.entries.count == 1)
            #expect(try await h.courses.courses(query: nil).count == 6)

            let first = try await h.writer.create(stats, actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: "k")
            #expect(first.entries == dry.entries)
            let again = try await h.writer.create(stats, actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: "k")
            #expect(again == first)
            #expect(try await h.courses.courses(query: nil).count == 7)
        }
    }

    @Test(arguments: createKinds)
    func createRejectsBadInput(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            func code(_ new: NewCourse) async -> String? {
                do { _ = try await h.writer.create(new, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil); return nil }
                catch let e as MarginError { return e.code } catch { return "other" }
            }
            var blank = stats; blank.name = "   "
            var noSemester = stats; noSemester.semester = "spring-2030"
            var badColor = stats; badColor.color = "chartreuse"
            var badLength = stats; badLength.sessions = [NewSession(day: .friday, start: .literal(8), lengthHours: 0)]
            var duplicate = stats; duplicate.name = "Cell Biology"
            #expect(await code(blank) == "invalid")
            #expect(await code(noSemester) == "notFound")
            #expect(await code(badColor) == "invalid")
            #expect(await code(badLength) == "invalid")
            #expect(await code(duplicate) == "conflict")
            let count = try await h.courses.courses(query: nil).count
            #expect(count == 6)
        }
    }

    // MARK: rename, colour, icon (M10-12.B)

    @Test(arguments: editKinds)
    func renameChangesTheNameAndKeepsTheId(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.courses.course(id: "bio")
            let noteCount = try await h.notes.notes(course: "bio").count
            let updates = h.courses.updates
            let cs = try await h.writer.rename(id: "bio", to: "Molecular Biology", renameFolder: false, actor: testActor,
                                               baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .modified && cs.entries[0].path.hasSuffix("/_course.md"))
            var expected = before; expected.name = "Molecular Biology"
            #expect(try await h.courses.course(id: "bio") == expected)
            #expect(try await h.notes.notes(course: "bio").count == noteCount)
            #expect(try await h.courses.courses(query: nil).map(\.id) == ["math", "econ", "hist", "bio", "chem", "phil"])
            #expect(await next(from: updates, where: { $0.courses == ["bio"] }) != nil)
            #expect(try await h.writer.courseVersion(id: "bio") == cs.entries[0].afterHash)
        }
    }

    @Test(arguments: editKinds)
    func renamingTheFolderMovesTheCourse(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let noteCount = try await h.notes.notes(course: "bio").count
            let cs = try await h.writer.rename(id: "bio", to: "Molecular Biology", renameFolder: true, actor: .user,
                                               baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .moved)
            #expect(cs.entries[0].path == "Fall 2026/Molecular Biology/_course.md")
            #expect(cs.entries[0].fromPath == "Fall 2026/Cell Biology/_course.md")
            #expect(try await h.courses.course(id: "bio").name == "Molecular Biology")
            #expect(try await h.notes.notes(course: "bio").count == noteCount)
            // A new folder name that is taken is refused.
            do {
                _ = try await h.writer.rename(id: "chem", to: "Molecular Biology", renameFolder: true, actor: .user,
                                              baseVersion: nil, dryRun: false, idempotencyKey: nil)
                Issue.record("a taken folder name should be refused")
            } catch let e as MarginError { #expect(e.code == "conflict") }
            #expect(try await h.courses.course(id: "chem").name == "Organic Chemistry")
        }
    }

    @Test(arguments: editKinds)
    func styleChangesIconAndColour(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.writer.setStyle(id: "bio", icon: "science", color: "econ", actor: testActor,
                                                 baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .modified)
            let bio = try await h.courses.course(id: "bio")
            #expect(bio.style == CoursePalette.style(icon: "science", color: "econ"))
            // Only the colour: the icon stays.
            _ = try await h.writer.setStyle(id: "bio", icon: nil, color: "phil", actor: .user, baseVersion: nil,
                                            dryRun: false, idempotencyKey: nil)
            let again = try await h.courses.course(id: "bio")
            #expect(again.style == CoursePalette.style(icon: "science", color: "phil"))
            // Setting what is already there writes nothing.
            let same = try await h.writer.setStyle(id: "bio", icon: "science", color: nil, actor: .user, baseVersion: nil,
                                                   dryRun: false, idempotencyKey: nil)
            #expect(same.isEmpty)
        }
    }

    @Test(arguments: editKinds)
    func editsHonourBaseVersionDryRunAndErrors(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let version = try await h.writer.courseVersion(id: "math")
            let dry = try await h.writer.rename(id: "math", to: "Calculus", renameFolder: false, actor: .user,
                                                baseVersion: version, dryRun: true, idempotencyKey: nil)
            #expect(dry.isDryRun && dry.entries.count == 1)
            #expect(try await h.courses.course(id: "math").name == "Linear Algebra")
            #expect(try await h.writer.courseVersion(id: "math") == version)

            _ = try await h.writer.rename(id: "math", to: "Calculus", renameFolder: false, actor: .user,
                                          baseVersion: version, dryRun: false, idempotencyKey: nil)
            // The version moved on: the old one is stale.
            func code(_ body: () async throws -> ChangeSet) async -> String? { await codeOf(body) }
            #expect(await code { try await h.writer.rename(id: "math", to: "Analysis", renameFolder: false, actor: .user,
                                                           baseVersion: version, dryRun: false, idempotencyKey: nil) } == "conflict")
            #expect(await code { try await h.writer.rename(id: "nope", to: "X", renameFolder: false, actor: .user,
                                                           baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "notFound")
            #expect(await code { try await h.writer.rename(id: "math", to: " ", renameFolder: false, actor: .user,
                                                           baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "invalid")
            #expect(await code { try await h.writer.setStyle(id: "math", icon: nil, color: "chartreuse", actor: .user,
                                                             baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "invalid")
            #expect(await code { try await h.writer.setStyle(id: "math", icon: nil, color: nil, actor: .user,
                                                             baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "invalid")
            let math = try await h.courses.course(id: "math")
            #expect(math.name == "Calculus")
        }
    }

    // MARK: archive (M10-13.B, M11-04.B)

    @Test(arguments: archiveKinds)
    func archivingASemesterMakesItReadOnlyAndIsReversible(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let coursesBefore = try await h.courses.courses(query: nil)
            let bioNotes = try await h.notes.notes(course: "bio").count
            let cs = try await h.writer.setArchived(semester: "fall-2026", true, actor: testActor, baseVersion: nil,
                                                    dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.first?.kind == .moved && cs.entries.first?.path == "_archive/Fall 2026"
                    && cs.entries.first?.fromPath == "Fall 2026")
            #expect(try await h.courses.semesters().map(\.isArchived) == [true])
            #expect(try await h.courses.courses(query: nil).isEmpty)          // no current semester any more
            #expect(try await h.courses.course(id: "bio").name == "Cell Biology")   // still readable
            // Its notes stay readable but cannot be written.
            let archivedNotes = try await h.notes.notes(course: "bio")
            #expect(archivedNotes.count == bioNotes)
            let note = try await h.notes.open(id: archivedNotes[0].id)
            #expect(note.summary.courseID == "bio")

            func code(_ body: () async throws -> ChangeSet) async -> String? { await codeOf(body) }
            #expect(await code { try await h.notes.create(course: "bio", title: "New", kind: .note, text: "", actor: .user,
                                                          baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "readOnly")
            #expect(await code { try await h.notes.save(id: note.summary.id, text: note.text + "x", actor: .user,
                                                        baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "readOnly")
            #expect(await code { try await h.notes.delete(id: note.summary.id, actor: .user, baseVersion: nil, dryRun: false,
                                                          idempotencyKey: nil) } == "readOnly")
            #expect(await code { try await h.notes.move(id: note.summary.id, toCourse: "chem", actor: .user, baseVersion: nil,
                                                        dryRun: false, idempotencyKey: nil) } == "readOnly")
            #expect(await code { try await h.writer.rename(id: "bio", to: "X", renameFolder: false, actor: .user,
                                                           baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "readOnly")
            #expect(await code { try await h.writer.create(stats, actor: .user, baseVersion: nil, dryRun: false,
                                                           idempotencyKey: nil) } == "readOnly")
            // Doing it twice changes nothing.
            let twice = try await h.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil,
                                                       dryRun: false, idempotencyKey: nil)
            #expect(twice.isEmpty)

            // Unarchiving restores everything.
            let back = try await h.writer.setArchived(semester: "fall-2026", false, actor: .user, baseVersion: nil,
                                                      dryRun: false, idempotencyKey: nil)
            #expect(back.entries.first?.kind == .moved && back.entries.first?.path == "Fall 2026")
            #expect(try await h.courses.semesters().map(\.isArchived) == [false])
            #expect(try await h.courses.courses(query: nil) == coursesBefore)
            #expect(try await h.notes.notes(course: "bio").count == bioNotes)
            _ = try await h.notes.create(course: "bio", title: "New", kind: .note, text: "", actor: .user,
                                         baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(await code { try await h.writer.setArchived(semester: "nope", true, actor: .user, baseVersion: nil,
                                                                dryRun: false, idempotencyKey: nil) } == "notFound")
        }
    }

    @Test(arguments: archiveKinds)
    func archiveDryRunChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let dry = try await h.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil,
                                                     dryRun: true, idempotencyKey: nil)
            #expect(dry.isDryRun && !dry.isEmpty)
            #expect(try await h.courses.semesters().map(\.isArchived) == [false])
            #expect(try await h.courses.courses(query: nil).count == 6)
        }
    }

    // MARK: overrides (M10-14.B)

    private let monday = LocalDate.literal(2026, 9, 28)

    @Test(arguments: overrideKinds)
    func cancellingOneClassKeepsItFlagged(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let tuesday = monday.adding(days: 1)
            let cs = try await h.writer.override(
                session: SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday, cancelled: true,
                                         note: "Professor ill"),
                actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .modified)
            let week = try await h.courses.sessions(week: 5)
            #expect(week.count == 11)
            let cancelled = try #require(week.first { $0.session.id == "bio-tue-1000" })
            #expect(cancelled.isCancelled && cancelled.date == tuesday && cancelled.note == "Professor ill")
            #expect(week.filter(\.isCancelled).count == 1)
            // Other weeks are untouched.
            #expect(try await h.courses.sessions(week: 6).allSatisfy { !$0.isCancelled })
        }
    }

    @Test(arguments: overrideKinds)
    func movingOneClassChangesItsTimeRoomAndDay(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let thursday = monday.adding(days: 3)
            let to = LocalDateTime(date: monday.adding(days: 4), time: .literal(14, 0))
            _ = try await h.writer.override(
                session: SessionOverride(sessionID: "bio-thu-1000", courseID: "bio", originalDate: thursday, newStart: to,
                                         newRoom: "Sci 300"),
                actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let week = try await h.courses.sessions(week: 5)
            let moved = try #require(week.first { $0.session.id == "bio-thu-1000" })
            #expect(!moved.isCancelled && moved.date == to.date && moved.originalDate == thursday)
            #expect(moved.session.start == .literal(14, 0) && moved.session.room == "Sci 300" && moved.start == to)
            #expect(moved.id == "bio-thu-1000@\(thursday.iso)")
            // The order follows the new day and time.
            #expect(week.map(\.date) == week.map(\.date).sorted())

            // Moved into the next week: gone from this one, present in the next.
            let next = LocalDateTime(date: monday.adding(days: 8), time: .literal(9, 0))
            _ = try await h.writer.override(
                session: SessionOverride(sessionID: "bio-thu-1000", courseID: "bio", originalDate: thursday, newStart: next),
                actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)   // replaces the earlier override
            #expect(try await h.courses.sessions(week: 5).count == 10)
            let week6 = try await h.courses.sessions(week: 6)
            #expect(week6.count == 12)
            #expect(week6.filter { $0.session.id == "bio-thu-1000" }.map(\.date) == [next.date, monday.adding(days: 10)].sorted())
        }
    }

    @Test(arguments: overrideKinds)
    func clearingAnOverrideRestoresTheTimetable(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.courses.sessions(week: 5)
            let tuesday = monday.adding(days: 1)
            _ = try await h.writer.override(
                session: SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday, cancelled: true),
                actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let cleared = try await h.writer.clearOverride(sessionID: "bio-tue-1000", course: "bio", originalDate: tuesday,
                                                           actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cleared.entries.count == 1)
            #expect(try await h.courses.sessions(week: 5) == before)
            let none = try await h.writer.clearOverride(sessionID: "bio-tue-1000", course: "bio", originalDate: tuesday,
                                                        actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(none.isEmpty)
        }
    }

    @Test(arguments: overrideKinds)
    func overridesAreValidated(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            func code(_ o: SessionOverride, dryRun: Bool = false, base: String? = nil) async -> String? {
                do { _ = try await h.writer.override(session: o, actor: .user, baseVersion: base, dryRun: dryRun, idempotencyKey: nil); return nil }
                catch let e as MarginError { return e.code } catch { return "other" }
            }
            let tuesday = monday.adding(days: 1)
            #expect(await code(SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: monday, cancelled: true)) == "invalid")   // not a Tuesday
            #expect(await code(SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday)) == "invalid")                 // changes nothing
            #expect(await code(SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: .literal(2027, 3, 2), cancelled: true)) == "invalid")   // outside the semester
            #expect(await code(SessionOverride(sessionID: "bio-fri-0900", courseID: "bio", originalDate: monday.adding(days: 4), cancelled: true)) == "notFound")
            #expect(await code(SessionOverride(sessionID: "x-tue-1000", courseID: "nope", originalDate: tuesday, cancelled: true)) == "notFound")
            #expect(await code(SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday, cancelled: true), base: "stale") == "conflict")
            // A dry run validates and changes nothing.
            #expect(await code(SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday, cancelled: true), dryRun: true) == nil)
            let week = try await h.courses.sessions(week: 5)
            #expect(week.allSatisfy { !$0.isCancelled })
        }
    }
}
