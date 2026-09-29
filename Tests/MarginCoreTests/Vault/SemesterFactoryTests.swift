import Foundation
import Testing
@testable import MarginCore

private func tempURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("margin-factory-\(UUID().uuidString)", isDirectory: true)
}

private let firstTerm = NewSemester(name: "Fall 2026", start: .literal(2026, 8, 31), end: .literal(2026, 12, 13), breakWeeks: [7])
private let tester = Actor.agent(identity: "study-helper", client: "factory-tests", session: "s-1", purpose: "test")

@Suite struct SemesterFactoryTests {
    private func isFolder(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    @Test func newVaultHasTheFoldersAndFiles() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let semester = try await SemesterFactory.initializeVault(at: url, firstSemester: firstTerm)
        #expect(semester.id == "fall-2026")
        for folder in ["_inbox", "_archive", "Fall 2026", ".margin"] { #expect(isFolder(url.appendingPathComponent(folder)), "\(folder)") }
        let semesters = try String(contentsOf: url.appendingPathComponent(".margin/semesters.json"), encoding: .utf8)
        let list = try JSONDecoder().decode([Semester].self, from: Data(semesters.utf8))
        #expect(list == [semester] && list[0].breakWeeks == [7])
        let settings = try String(contentsOf: url.appendingPathComponent(".margin/settings.json"), encoding: .utf8)
        #expect((try JSONSerialization.jsonObject(with: Data(settings.utf8)) as? [String: Any])?.isEmpty == true)
    }

    @Test func newVaultOpensAndEveryServiceAnswersEmpty() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await SemesterFactory.initializeVault(at: url, firstSemester: firstTerm)
        let env = try await AppEnvironment.vault(at: url, clock: FixedClock(), watchInterval: 0.05)

        #expect(try await env.courses.semesters().map(\.name) == ["Fall 2026"])
        #expect(try await env.courses.courses(query: nil).isEmpty)
        #expect(try await env.courses.courses(query: "bio").isEmpty)
        let semester = try #require(try await env.semesters.current())
        for week in 1...semester.weekCount { #expect(try await env.courses.sessions(week: week).isEmpty) }
        #expect(try await env.notes.notes(course: nil).isEmpty)
        #expect(try await env.tasks.today().isEmpty)
        #expect(try await env.tasks.upcoming().isEmpty)
        #expect(try await env.inbox.items().isEmpty)
        // The property registry holds the built-in keys (date, class, …) and nothing inferred from notes.
        let types = try await env.properties.types()
        #expect(!types.isEmpty && types["my-own-key"] == nil)
        let graph = try await env.graph.graph(scope: .all, filter: .none)
        #expect(graph.nodes.isEmpty && graph.edges.isEmpty)
        // Settings read as defaults, and the capture parser answers (it does not need a course).
        #expect(await env.settings.get(Settings.reminderMinutes) == 10)
        _ = try await env.capture.parse("Read chapter 3 by friday")
        await env.shutdown()
    }

    @Test func newVaultAcceptsItsFirstCourseAndNote() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await SemesterFactory.initializeVault(at: url, firstSemester: firstTerm)
        let env = try await AppEnvironment.vault(at: url, clock: FixedClock(), watchInterval: 0.05)
        _ = try await env.courseWriter.create(NewCourse(name: "Biology", semester: "fall-2026", code: "BIO 1"), actor: tester,
                                              baseVersion: nil, dryRun: false, idempotencyKey: nil)
        _ = try await env.notes.create(course: "biology", title: "First lecture", kind: .lecture, text: "- [ ] Read ch. 1",
                                       actor: tester, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(try await env.notes.notes(course: "biology").count == 1)
        #expect(try await env.tasks.tasks(course: "biology").count == 1)
        await env.shutdown()
    }

    @Test func aSemesterCreatedLaterGetsItsFolder() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await SemesterFactory.initializeVault(at: url, firstSemester: firstTerm)
        let env = try await AppEnvironment.vault(at: url, clock: FixedClock(), watchInterval: 0.05)
        let dry = try await env.semesters.create(NewSemester(name: "Spring 2027", start: .literal(2027, 2, 15), end: .literal(2027, 5, 30)),
                                                 actor: tester, baseVersion: nil, dryRun: true, idempotencyKey: nil)
        #expect(dry.isDryRun && !isFolder(url.appendingPathComponent("Spring 2027")))
        _ = try await env.semesters.create(NewSemester(name: "Spring 2027", start: .literal(2027, 2, 15), end: .literal(2027, 5, 30)),
                                           actor: tester, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(isFolder(url.appendingPathComponent("Spring 2027")))
        // A course can be made in it right away.
        _ = try await env.courseWriter.create(NewCourse(name: "Statistics", semester: "spring-2027"), actor: tester,
                                              baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("Spring 2027/Statistics/_course.md").path))
        await env.shutdown()
    }

    @Test func existingFoldersAreNeverInitializedOver() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let note = url.appendingPathComponent("Mine.md")
        try Data("keep me".utf8).write(to: note)
        await #expect(throws: MarginError.self) { try await SemesterFactory.initializeVault(at: url, firstSemester: firstTerm) }
        #expect(try String(contentsOf: note, encoding: .utf8) == "keep me")
        #expect(!isFolder(url.appendingPathComponent(".margin")) && !isFolder(url.appendingPathComponent("_inbox")))

        // A second initialization of an initialized vault fails too and keeps the first one.
        let fresh = tempURL()
        defer { try? FileManager.default.removeItem(at: fresh) }
        try await SemesterFactory.initializeVault(at: fresh, firstSemester: firstTerm)
        await #expect(throws: MarginError.self) {
            try await SemesterFactory.initializeVault(at: fresh, firstSemester: NewSemester(name: "Other", start: .literal(2026, 8, 31), end: .literal(2026, 12, 13)))
        }
        let list = try JSONDecoder().decode([Semester].self, from: Data(contentsOf: fresh.appendingPathComponent(".margin/semesters.json")))
        #expect(list.map(\.name) == ["Fall 2026"])
    }

    @Test func aFileInPlaceOfTheFolderIsInvalid() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("x".utf8).write(to: url)
        do { _ = try await SemesterFactory.initializeVault(at: url, firstSemester: firstTerm); Issue.record("expected an error") }
        catch let e as MarginError { #expect(e.code == "invalid") }
    }

    @Test func badSemestersAreRejectedBeforeAnythingIsWritten() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        for bad in [NewSemester(name: "", start: .literal(2026, 8, 31), end: .literal(2026, 12, 13)),
                    NewSemester(name: "Fall", start: .literal(2026, 9, 1), end: .literal(2026, 12, 13)),
                    NewSemester(name: "Fall", start: .literal(2026, 8, 31), end: .literal(2026, 8, 1))] {
            do { _ = try await SemesterFactory.initializeVault(at: url, firstSemester: bad); Issue.record("expected an error") }
            catch let e as MarginError { #expect(e.code == "invalid") }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func createsMissingParentFolders() async throws {
        let parent = tempURL()
        defer { try? FileManager.default.removeItem(at: parent) }
        let url = parent.appendingPathComponent("a/b/Vault", isDirectory: true)
        try await SemesterFactory.initializeVault(at: url, firstSemester: firstTerm)
        #expect(isFolder(url.appendingPathComponent("_inbox")))
    }

    @Test(arguments: [
        (LocalDate.literal(2026, 9, 28), "Fall 2026", LocalDate.literal(2026, 9, 7)),
        (LocalDate.literal(2026, 8, 3), "Fall 2026", LocalDate.literal(2026, 9, 7)),
        (LocalDate.literal(2027, 1, 12), "Fall 2026", LocalDate.literal(2026, 9, 7)),
        (LocalDate.literal(2027, 3, 1), "Spring 2027", LocalDate.literal(2027, 2, 15)),
        (LocalDate.literal(2027, 7, 31), "Spring 2027", LocalDate.literal(2027, 2, 15)),
    ])
    func suggestedSemesterFitsTheDate(today: LocalDate, name: String, start: LocalDate) throws {
        #expect(SemesterFactory.suggestedSemester(today: today).start == start)
        let s = SemesterFactory.suggestedSemester(today: today)
        #expect(s.name == name)
        #expect(s.start.weekday == .monday && s.start.days(to: s.end) == 15 * 7 - 1)
        // The suggestion is always a valid semester.
        #expect(throws: Never.self) { try SemesterRules.make(s, among: []) }
    }
}
