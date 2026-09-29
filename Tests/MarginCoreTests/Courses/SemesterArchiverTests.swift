import Foundation
import Testing
@testable import MarginCore

/// M10-13.B and M11-04.B: archiving moves a semester to `_archive/`, marks it read-only, is fully
/// reversible, and every write into it is rejected.
@Suite struct SemesterArchiverTests {
    private func files(_ v: CourseVault, under prefix: String) -> [String: Data] {
        var result: [String: Data] = [:]
        for (path, data) in v.dir.snapshot() where path.hasPrefix(prefix + "/") { result[String(path.dropFirst(prefix.count + 1))] = data }
        return result
    }

    @Test func archivingMovesTheFolderByteForByteAndFlagsTheSemester() async throws {
        let v = try await CourseVault.open()
        let original = files(v, under: "Fall 2026")
        #expect(original.count > 6)

        let cs = try await v.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(cs.entries.map(\.kind) == [.moved, .modified])
        #expect(cs.entries[0].path == "_archive/Fall 2026" && cs.entries[0].fromPath == "Fall 2026")
        #expect(cs.entries[1].path == ".margin/semesters.json")
        #expect(!v.dir.exists("Fall 2026"))
        #expect(files(v, under: "_archive/Fall 2026") == original)                 // nothing lost, nothing changed
        let json = v.text(".margin/semesters.json")
        #expect(json.contains("\"archived\" : true") && json.contains("\"id\" : \"fall-2026\""), "\(json)")
        #expect(ContentHash(of: json).hex == cs.entries[1].afterHash)
        #expect(v.dir.temporaryFiles.isEmpty)

        #expect(try await v.catalog.semesters().map(\.isArchived) == [true])
        #expect(try await v.catalog.courses(query: nil).isEmpty)
        #expect(try await v.catalog.course(id: "bio").name == "Cell Biology")
        await v.shutdown()

        // It is the same after a restart.
        let again = try await CourseVault.reopen(v.dir)
        #expect(try await again.catalog.semesters().map(\.isArchived) == [true])
        #expect(try await again.catalog.courses(query: nil).isEmpty)
        #expect(try await again.catalog.course(id: "bio").semester == "fall-2026")
        await again.shutdown()
    }

    @Test func unarchivingRestoresTheVaultExactly() async throws {
        let v = try await CourseVault.open()
        let original = files(v, under: "Fall 2026")
        let coursesBefore = try await v.catalog.courses(query: nil)
        let notesBefore = try await v.notes.notes(course: nil).map(\.id)
        let todayBefore = try await v.tasks.today().map(\.id)

        _ = try await v.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        let cs = try await v.writer.setArchived(semester: "fall-2026", false, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(cs.entries.first?.kind == .moved && cs.entries.first?.path == "Fall 2026")
        #expect(files(v, under: "Fall 2026") == original)
        #expect(!v.dir.exists("_archive/Fall 2026"))
        #expect(!v.text(".margin/semesters.json").contains("archived"))
        #expect(try await v.catalog.courses(query: nil) == coursesBefore)
        #expect(try await v.notes.notes(course: nil).map(\.id) == notesBefore)
        #expect(try await v.tasks.today().map(\.id) == todayBefore)
        // Writable again.
        let note = try await v.notes.create(course: "bio", title: "After", kind: .note, text: "", actor: .user, baseVersion: nil,
                                            dryRun: false, idempotencyKey: nil)
        #expect(note.entries.count == 1)
        await v.shutdown()
    }

    @Test func nothingInsideAnArchivedSemesterCanBeWritten() async throws {
        let v = try await CourseVault.open()
        let live = try await v.notes.notes(course: "bio")
        let taskNote = try #require(try await v.notes.notes(course: "bio").first { $0.openTasks > 0 })
        _ = try await v.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        let snapshot = v.dir.snapshot()

        // Readable ...
        let archived = try await v.notes.notes(course: "bio")
        #expect(archived.map(\.id) == live.map(\.id))
        let note = try await v.notes.open(id: taskNote.id)
        #expect(note.summary.courseID == "bio" && !note.text.isEmpty)
        // ... but not part of the live lists.
        #expect(try await v.notes.notes(course: nil).isEmpty)
        let today = try await v.tasks.today(), upcoming = try await v.tasks.upcoming()
        #expect(today.isEmpty && upcoming.isEmpty)

        // Every write is refused with .readOnly, and the files do not change.
        var codes: [String?] = []
        codes.append(await errorCode { try await v.notes.save(id: note.summary.id, text: "new", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) })
        codes.append(await errorCode { try await v.notes.save(id: note.summary.id, text: "new", actor: .user, baseVersion: note.version, dryRun: true, idempotencyKey: nil) })
        codes.append(await errorCode { try await v.notes.delete(id: note.summary.id, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) })
        codes.append(await errorCode { try await v.notes.move(id: note.summary.id, toCourse: "chem", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) })
        codes.append(await errorCode { try await v.notes.create(course: "bio", title: "New", kind: .note, text: "", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) })
        codes.append(await errorCode { try await v.writer.rename(id: "bio", to: "X", renameFolder: true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) })
        codes.append(await errorCode { try await v.writer.setStyle(id: "bio", icon: "x", color: nil, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) })
        codes.append(await errorCode { try await v.writer.create(NewCourse(name: "Fresh", semester: "fall-2026"), actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) })
        #expect(codes == Array(repeating: "readOnly", count: codes.count), "\(codes)")
        #expect(v.dir.snapshot() == snapshot)
        await v.shutdown()
    }

    @Test func dryRunAndRepeatedCallsChangeNothing() async throws {
        let v = try await CourseVault.open()
        let before = v.dir.snapshot()
        let dry = try await v.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: true, idempotencyKey: nil)
        #expect(dry.isDryRun && dry.entries.map(\.kind) == [.moved, .modified])
        #expect(v.dir.snapshot() == before)

        let first = try await v.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: "a")
        let same = try await v.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: "a")
        #expect(same == first)
        let twice = try await v.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(twice.isEmpty)
        await v.shutdown()
    }

    @Test func aTakenTargetIsAConflictAndNothingMoves() async throws {
        let v = try await CourseVault.open()
        try v.dir.seed("_archive/Fall 2026/Old.md", Data("old\n".utf8))
        let before = v.dir.snapshot()
        let code = await errorCode { try await v.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
        #expect(code == "conflict")
        #expect(v.dir.snapshot() == before)
        let unknown = await errorCode { try await v.writer.setArchived(semester: "nope", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
        #expect(unknown == "notFound")
        await v.shutdown()
    }

    @Test func aSemesterWithoutCoursesIsArchivedThroughTheFlagAlone() async throws {
        let dir = TempDir()
        try dir.seed(".margin/semesters.json", Data("""
            [
              {"id": "spring-2026", "name": "Spring 2026", "start": "2026-02-02", "end": "2026-06-05", "breakWeeks": [8]},
              {"id": "fall-2026", "name": "Fall 2026", "start": "2026-08-31", "end": "2026-12-18", "breakWeeks": []}
            ]
            """.utf8))
        let v = try await CourseVault.reopen(dir)
        let cs = try await v.writer.setArchived(semester: "spring-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(cs.entries.map(\.kind) == [.modified])                  // no folder to move
        let semesters = try await v.catalog.semesters()
        #expect(semesters.map(\.isArchived) == [true, false] && semesters[0].breakWeeks == [8])
        let code = await errorCode { try await v.writer.create(NewCourse(name: "Late", semester: "spring-2026"), actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
        #expect(code == "readOnly")
        // The other semester was not touched.
        _ = try await v.writer.create(NewCourse(name: "On Time", semester: "fall-2026"), actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        await v.shutdown()
    }

    @Test func aSemestersFileThatIsNotJSONIsNotOverwritten() async throws {
        let v = try await CourseVault.open()
        try v.dir.seed(".margin/semesters.json", Data("this is my own note, not json\n".utf8))
        let before = v.dir.snapshot()
        // The model cannot read the file, so it made a placeholder semester from the folder; archiving must not clobber the file.
        let id = try #require(try await v.catalog.semesters().first?.id)
        let code = await errorCode { try await v.writer.setArchived(semester: id, true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
        #expect(code == "invalid")
        #expect(v.dir.snapshot() == before)
        await v.shutdown()
    }
}
