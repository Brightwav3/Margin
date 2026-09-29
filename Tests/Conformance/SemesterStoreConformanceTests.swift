import Foundation
import Testing
@testable import MarginCore

private func codeOf<T>(_ body: () async throws -> T) async -> String? {
    do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other" }
}

private let spring = NewSemester(name: "Spring 2027", start: .literal(2027, 2, 15), end: .literal(2027, 5, 30), breakWeeks: [8])

/// `SemesterStore` (M11-05.B), run against `FixtureSemesterStore` and `VaultSemesterStore`.
@Suite struct SemesterStoreConformanceTests {
    private func create(_ h: Harness, _ new: NewSemester = spring, base: String? = nil, dryRun: Bool = false,
                        key: String? = nil) async throws -> ChangeSet {
        try await h.semesters.create(new, actor: testActor, baseVersion: base, dryRun: dryRun, idempotencyKey: key)
    }

    private func update(_ h: Harness, _ id: SemesterID, _ u: SemesterUpdate, base: String? = nil,
                        dryRun: Bool = false) async throws -> ChangeSet {
        try await h.semesters.update(id: id, u, actor: testActor, baseVersion: base, dryRun: dryRun, idempotencyKey: nil)
    }

    @Test(arguments: HarnessKind.allCases)
    func startsWithTheFallSemester(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let list = try await h.semesters.semesters()
            #expect(list.map(\.id) == ["fall-2026"])
            #expect(try await h.semesters.current()?.id == "fall-2026")
            #expect(try await h.semesters.semesters() == h.courses.semesters())
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func createAddsASemesterTheCatalogShows(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.semesters.version()
            let cs = try await create(h)
            #expect(cs.entries.map(\.path) == [".margin/semesters.json"] && cs.actor == testActor)
            let list = try await h.courses.semesters()
            #expect(list.map(\.id) == ["fall-2026", "spring-2027"])
            let s = try #require(list.last)
            #expect(s.name == "Spring 2027" && s.start == .literal(2027, 2, 15) && s.end == .literal(2027, 5, 30))
            #expect(s.breakWeeks == [8] && !s.isArchived)
            #expect(try await h.semesters.semesters() == list)
            #expect(try await h.semesters.version() != before)
            // Today is still in the fall semester.
            #expect(try await h.semesters.current()?.id == "fall-2026")
            #expect(try await h.courses.courses(query: nil).count == 6)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func nameIsTrimmedBreakWeeksAreSortedAndUnique(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await create(h, NewSemester(name: "  Spring 2027 ", start: .literal(2027, 2, 15),
                                                end: .literal(2027, 5, 30), breakWeeks: [9, 3, 9, 3]))
            let s = try #require(try await h.semesters.semesters().last)
            #expect(s.name == "Spring 2027" && s.id == "spring-2027" && s.breakWeeks == [3, 9])
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func dryRunAndIdempotencyKey(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let dry = try await create(h, dryRun: true)
            #expect(dry.isDryRun && dry.entries.count == 1)
            #expect(try await h.semesters.semesters().count == 1)
            let first = try await create(h, key: "k1")
            let again = try await create(h, key: "k1")
            #expect(again == first)
            #expect(try await h.semesters.semesters().count == 2)
            // The dry run announced what the real write then did.
            #expect(dry.entries[0].afterHash == first.entries[0].afterHash)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func invalidInputIsRejectedAndNothingChanges(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            func bad(_ name: String = "Spring 2027", start: LocalDate = .literal(2027, 2, 15),
                     end: LocalDate = .literal(2027, 5, 30), weeks: [Int] = []) async -> String? {
                await codeOf { try await create(h, NewSemester(name: name, start: start, end: end, breakWeeks: weeks)) }
            }
            #expect(await bad("   ") == "invalid")
            #expect(await bad("_hidden") == "invalid")
            #expect(await bad(".hidden") == "invalid")
            #expect(await bad("a/b") == "invalid")
            #expect(await bad("!!!") == "invalid")
            #expect(await bad(start: .literal(2027, 2, 16)) == "invalid", "not a Monday")
            #expect(await bad(end: .literal(2027, 2, 14)) == "invalid", "ends before it starts")
            #expect(await bad(weeks: [0]) == "invalid")
            #expect(await bad(weeks: [99]) == "invalid")
            #expect(await bad(weeks: [-1]) == "invalid")
            let count = try await h.semesters.semesters().count
            #expect(count == 1)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func duplicateNamesAndIdsConflict(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await create(h)
            #expect(await codeOf { try await create(h) } == "conflict")
            #expect(await codeOf { try await create(h, NewSemester(name: "spring 2027", start: .literal(2027, 2, 15),
                                                                   end: .literal(2027, 5, 30))) } == "conflict")
            #expect(await codeOf { try await create(h, NewSemester(name: "fall-2026", start: .literal(2027, 2, 15),
                                                                   end: .literal(2027, 5, 30))) } == "conflict")
            #expect(try await h.semesters.semesters().count == 2)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func staleBaseVersionConflicts(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.semesters.version()
            _ = try await create(h, base: v0)
            #expect(await codeOf { try await create(h, NewSemester(name: "Summer 2027", start: .literal(2027, 6, 7),
                                                                   end: .literal(2027, 8, 1)), base: v0) } == "conflict")
            #expect(await codeOf { try await update(h, "spring-2027", SemesterUpdate(breakWeeks: []), base: v0) } == "conflict")
            #expect(await codeOf { try await h.semesters.delete(id: "spring-2027", actor: testActor, baseVersion: v0,
                                                               dryRun: false, idempotencyKey: nil) } == "conflict")
            let v1 = try await h.semesters.version()
            _ = try await update(h, "spring-2027", SemesterUpdate(breakWeeks: []), base: v1)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func updateChangesDatesAndBreakWeeks(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await create(h)
            let cs = try await update(h, "spring-2027", SemesterUpdate(end: .literal(2027, 6, 6), breakWeeks: [12, 4, 4]))
            #expect(cs.entries.map(\.path) == [".margin/semesters.json"])
            let s = try #require(try await h.courses.semesters().last)
            #expect(s.end == .literal(2027, 6, 6) && s.breakWeeks == [4, 12] && s.start == .literal(2027, 2, 15))
            #expect(s.name == "Spring 2027" && s.id == "spring-2027")

            let same = try await update(h, "spring-2027", SemesterUpdate(end: .literal(2027, 6, 6)))
            #expect(same.entries.isEmpty, "nothing changed")
            let dry = try await update(h, "spring-2027", SemesterUpdate(start: .literal(2027, 2, 22)), dryRun: true)
            #expect(dry.isDryRun && dry.entries.count == 1)
            #expect(try await h.courses.semesters().last?.start == .literal(2027, 2, 15))

            #expect(await codeOf { try await update(h, "spring-2027", SemesterUpdate(breakWeeks: [40])) } == "invalid")
            #expect(await codeOf { try await update(h, "spring-2027", SemesterUpdate(end: .literal(2027, 3, 1))) } == "invalid",
                    "the kept break weeks no longer fit")
            #expect(await codeOf { try await update(h, "spring-2027", SemesterUpdate(start: .literal(2027, 2, 16))) } == "invalid")
            #expect(await codeOf { try await update(h, "nope", SemesterUpdate(breakWeeks: [])) } == "notFound")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func renameGivesANewIdAndKeepsTheCourses(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await update(h, "fall-2026", SemesterUpdate(name: "Autumn 2026"))
            #expect(cs.entries.contains { $0.kind == .moved && $0.path == "Autumn 2026" && $0.fromPath == "Fall 2026" })
            let list = try await h.courses.semesters()
            #expect(list.map(\.id) == ["autumn-2026"] && list[0].name == "Autumn 2026")
            let courses = try await h.courses.courses(query: nil)
            #expect(courses.count == 6 && courses.allSatisfy { $0.semester == "autumn-2026" })
            #expect(courses.map(\.id).contains("bio"), "course ids are stable")
            #expect(try await h.semesters.current()?.id == "autumn-2026")
            #expect(try await h.courses.sessions(week: 5).count == 11)
            #expect(await codeOf { try await update(h, "autumn-2026", SemesterUpdate(name: "")) } == "invalid")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func renameToATakenNameConflicts(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await create(h)
            #expect(await codeOf { try await update(h, "spring-2027", SemesterUpdate(name: "fall 2026")) } == "conflict")
            _ = try await update(h, "spring-2027", SemesterUpdate(name: "Spring 2027"))   // same name: no-op
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func deleteRemovesAnEmptySemester(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await create(h)
            let dry = try await h.semesters.delete(id: "spring-2027", actor: testActor, baseVersion: nil, dryRun: true,
                                                   idempotencyKey: nil)
            #expect(dry.isDryRun && dry.entries.count == 1)
            #expect(try await h.semesters.semesters().count == 2)
            let cs = try await h.semesters.delete(id: "spring-2027", actor: testActor, baseVersion: nil, dryRun: false,
                                                  idempotencyKey: nil)
            #expect(cs.entries.map(\.path) == [".margin/semesters.json"])
            #expect(try await h.courses.semesters().map(\.id) == ["fall-2026"])
            #expect(await codeOf { try await h.semesters.delete(id: "spring-2027", actor: testActor, baseVersion: nil,
                                                               dryRun: false, idempotencyKey: nil) } == "notFound")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aSemesterWithCoursesCannotBeDeleted(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            #expect(await codeOf { try await h.semesters.delete(id: "fall-2026", actor: testActor, baseVersion: nil,
                                                               dryRun: false, idempotencyKey: nil) } == "conflict")
            let count = try await h.courses.courses(query: nil).count
            #expect(count == 6)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func archivedSemestersAreReadOnly(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await create(h)
            _ = try await h.writer.setArchived(semester: "spring-2027", true, actor: testActor, baseVersion: nil,
                                               dryRun: false, idempotencyKey: nil)
            let archived = try #require(try await h.semesters.semesters().first { $0.id == "spring-2027" })
            #expect(archived.isArchived)
            #expect(await codeOf { try await update(h, "spring-2027", SemesterUpdate(breakWeeks: [])) } == "readOnly")
            #expect(await codeOf { try await update(h, "spring-2027", SemesterUpdate(name: "Other")) } == "readOnly")
            #expect(await codeOf { try await h.semesters.delete(id: "spring-2027", actor: testActor, baseVersion: nil,
                                                               dryRun: false, idempotencyKey: nil) } == "readOnly")
            // Restoring makes it writable again.
            _ = try await h.writer.setArchived(semester: "spring-2027", false, actor: testActor, baseVersion: nil,
                                               dryRun: false, idempotencyKey: nil)
            _ = try await update(h, "spring-2027", SemesterUpdate(breakWeeks: []))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func currentSemesterFollowsTheClock(kind: HarnessKind) async throws {
        let inSpring = FixedClock(local: LocalDateTime(date: .literal(2027, 3, 1), time: .literal(9, 0)))
        try await withHarness(kind, clock: inSpring) { h in
            // Only the fall semester exists: the latest one that started is current.
            #expect(try await h.semesters.current()?.id == "fall-2026")
            _ = try await create(h)
            #expect(try await h.semesters.current()?.id == "spring-2027")
            // The catalog follows: the new semester has no courses yet.
            #expect(try await h.courses.courses(query: nil).isEmpty)
            // An archived semester is never current.
            _ = try await h.writer.setArchived(semester: "spring-2027", true, actor: testActor, baseVersion: nil,
                                               dryRun: false, idempotencyKey: nil)
            #expect(try await h.semesters.current()?.id == "fall-2026")
        }
    }

    // MARK: Vault file

    @Test func vaultWritesTheArrayFormatOfSemestersJSON() async throws {
        try await withHarness(.vault) { h in
            _ = try await create(h)
            _ = try await update(h, "fall-2026", SemesterUpdate(breakWeeks: [6]))
            let text = try #require(h.readFile(".margin/semesters.json"))
            let list = try JSONDecoder().decode([Semester].self, from: Data(text.utf8))
            #expect(list.map(\.id) == ["fall-2026", "spring-2027"])
            #expect(list[0].breakWeeks == [6] && list[1].breakWeeks == [8] && list[1].start == .literal(2027, 2, 15))
            #expect(text.hasSuffix("\n"))
        }
    }

    @Test func vaultRenameMovesTheFolderAndKeepsTheNotes() async throws {
        try await withHarness(.vault) { h in
            let notesBefore = try await h.notes.notes(course: "bio").count
            #expect(notesBefore > 0)
            _ = try await update(h, "fall-2026", SemesterUpdate(name: "Autumn 2026"))
            #expect(h.listFiles("Fall 2026").isEmpty)
            #expect(h.listFiles("Autumn 2026/Cell Biology").contains("Lecture 8 — Cell membrane.md"))
            #expect(try await h.notes.notes(course: "bio").count == notesBefore)
            let note = try await h.notes.open(id: "bio/lecture-8")
            #expect(note.summary.courseID == "bio")
            let list = try JSONDecoder().decode([Semester].self, from: Data(try #require(h.readFile(".margin/semesters.json")).utf8))
            #expect(list.map(\.name) == ["Autumn 2026"])
        }
    }

    @Test func vaultKeepsWorkingOnAHandEditedFileAndRefusesABrokenOne() async throws {
        try await withHarness(.vault) { h in
            try h.writeFile(".margin/semesters.json", "not json")
            #expect(await codeOf { try await create(h) } == "invalid")
            #expect(h.readFile(".margin/semesters.json") == "not json", "a broken file is not overwritten")
        }
    }

    @Test func vaultPersistsAcrossReopening() async throws {
        let folder = TempFolder()
        let store = try await VaultStore.open(root: folder.url, createIfMissing: true)
        try await SampleVaultGenerator.generate(into: store, from: Fixtures.week5)
        let first = try await AppEnvironment.vault(at: folder.url, clock: FixedClock(), watchInterval: 0.05)
        _ = try await first.semesters.create(spring, actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        _ = try await first.semesters.update(id: "spring-2027", SemesterUpdate(breakWeeks: [2, 5]), actor: testActor,
                                             baseVersion: nil, dryRun: false, idempotencyKey: nil)
        await first.shutdown()

        let second = try await AppEnvironment.vault(at: folder.url, clock: FixedClock(), watchInterval: 0.05)
        let list = try await second.semesters.semesters()
        #expect(list.map(\.id) == ["fall-2026", "spring-2027"])
        #expect(list[1].breakWeeks == [2, 5])
        #expect(try await second.semesters.current()?.id == "fall-2026")
        await second.shutdown()
    }
}
