import Foundation
import Testing
@testable import MarginCore

/// The write context and the service protocols of contract rules 0 and 2 (`docs/plan/09-contracts.md`):
/// value types survive JSON, and the protocols can be implemented by code that knows only `API/`
/// (the UI replaceability rule).
@Suite struct ServiceContractTypesTests {
    typealias WriteActor = Actor

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @Test func actorRoundTripsAndHasStableShape() throws {
        let agent = WriteActor.agent(identity: "study-helper", client: "claude-code", session: "s-1", purpose: "plan the week")
        for actor in [WriteActor.user, .system, agent, .agent(identity: "x", client: "y", session: "z")] {
            #expect(try roundTrip(actor) == actor)
        }
        let json = String(decoding: try JSONEncoder().encode(WriteActor.user), as: UTF8.self)
        #expect(json == #"{"kind":"user"}"#)
        #expect(agent.label == "agent:study-helper/s-1")
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WriteActor.self, from: Data(#"{"kind":"robot"}"#.utf8))
        }
    }

    @Test func changeSetRoundTrips() throws {
        let cs = ChangeSet(
            id: "cs-1", actor: .user, timestamp: Date(timeIntervalSince1970: 1_790_000_000),
            entries: [
                .init(path: "a.md", kind: .created, noteID: "bio/a", afterHash: "aa"),
                .init(path: "b.md", kind: .modified, noteID: "bio/b", beforeHash: "b1", afterHash: "b2"),
                .init(path: "c.md", kind: .moved, noteID: "bio/c", fromPath: "old/c.md", beforeHash: "c1", afterHash: "c1"),
                .init(path: "d.md", kind: .deleted, beforeHash: "d1"),
            ],
            isDryRun: true, idempotencyKey: "k")
        #expect(try roundTrip(cs) == cs)
        #expect(!cs.isEmpty)
        #expect(ChangeSet(id: "e", actor: .system, timestamp: Date(timeIntervalSince1970: 0), entries: []).isEmpty)
    }

    @Test func sessionOccurrenceHasStableIDAndStart() throws {
        let session = Session(courseID: "bio", day: .tuesday, start: .literal(10), lengthHours: 1.5, kind: "Lecture")
        let occurrence = SessionOccurrence(session: session, date: .literal(2026, 9, 29))
        #expect(occurrence.id == "bio-tue-1000@2026-09-29")
        #expect(occurrence.start == LocalDateTime(date: .literal(2026, 9, 29), time: .literal(10)))
        #expect(try roundTrip(occurrence) == occurrence)
        #expect(try roundTrip(CatalogUpdate(courses: ["b", "a"])).courses == ["a", "b"])
        #expect(try roundTrip(NoteChange(noteID: "bio/a", kind: .deleted)) == NoteChange(noteID: "bio/a", kind: .deleted))
    }

    // Stubs that know only the API: if a protocol changes shape, this stops compiling (rule 8).
    struct StubCatalog: CourseCatalog {
        func semesters() async throws -> [Semester] { [] }
        func courses(query: String?) async throws -> [Course] { [] }
        func course(id: CourseID) async throws -> Course { throw MarginError.notFound(id) }
        func sessions(week: Int) async throws -> [SessionOccurrence] { [] }
        var updates: AsyncStream<CatalogUpdate> { AsyncStream { $0.finish() } }
    }

    struct StubNotes: NoteRepository {
        func notes(course: CourseID?) async throws -> [NoteSummary] { [] }
        func open(id: NoteID) async throws -> Note { throw MarginError.notFound(id) }
        func save(id: NoteID, text: String, actor: WriteActor, baseVersion: String?, dryRun: Bool,
                  idempotencyKey: String?) async throws -> ChangeSet { throw MarginError.notFound(id) }
        func create(course: CourseID, title: String, kind: NoteKind, text: String, actor: WriteActor,
                    baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
            throw MarginError.notFound(course)
        }
        func move(id: NoteID, toCourse: CourseID, actor: WriteActor, baseVersion: String?, dryRun: Bool,
                  idempotencyKey: String?) async throws -> ChangeSet { throw MarginError.notFound(id) }
        func delete(id: NoteID, actor: WriteActor, baseVersion: String?, dryRun: Bool,
                    idempotencyKey: String?) async throws -> ChangeSet { throw MarginError.notFound(id) }
        var externalChanges: AsyncStream<[NoteChange]> { AsyncStream { $0.finish() } }
    }

    struct StubTasks: TaskService {
        func today() async throws -> [TaskItem] { [] }
        func upcoming() async throws -> [TaskItem] { [] }
        func tasks(course: CourseID) async throws -> [TaskItem] { throw MarginError.notFound(course) }
        func toggle(id: String, actor: WriteActor, baseVersion: String?, dryRun: Bool,
                    idempotencyKey: String?) async throws -> ChangeSet { throw MarginError.notFound(id) }
        var updates: AsyncStream<TaskUpdate> { AsyncStream { $0.finish() } }
    }

    @Test func protocolsCanBeImplementedFromTheAPIAlone() async throws {
        let catalog: any CourseCatalog = StubCatalog()
        let notes: any NoteRepository = StubNotes()
        let tasks: any TaskService = StubTasks()
        #expect(try await catalog.courses(query: nil).isEmpty)
        await #expect(throws: MarginError.self) { try await notes.open(id: "x") }
        await #expect(throws: MarginError.self) { try await tasks.tasks(course: "x") }
    }
}
