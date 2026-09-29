import Foundation
import Testing
@testable import MarginCore

/// Which implementation of the services a conformance test runs against (contract §5). Every
/// suite is parameterised over these, so a fixture that behaves differently from the vault fails
/// its own test.
enum HarnessKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case fixture, vault
    var testDescription: String { rawValue }
}

/// A removable temp folder.
final class TempFolder: @unchecked Sendable {
    let url: URL
    init() {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("margin-conformance-\(UUID().uuidString)", isDirectory: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// One `AppEnvironment` plus the means to change its data "behind its back", the way another
/// program would (fixture: through the in-memory store; vault: by writing files directly).
struct Harness: Sendable {
    let kind: HarnessKind
    let env: AppEnvironment
    /// The write side of the course catalog (`CourseCatalogWriter`); shares its state with `courses`.
    let writer: any CourseCatalogWriter
    /// Replaces the body of a note from outside.
    let editNote: @Sendable (NoteID, String) async throws -> Void
    /// The whole file content of a note: frontmatter and body, byte for byte.
    let rawContent: @Sendable (NoteID) async throws -> String
    /// Deletes a note from outside.
    let deleteNote: @Sendable (NoteID) async throws -> Void
    /// Changes the room of a course from outside.
    let editCourseRoom: @Sendable (CourseID, String) async throws -> Void
    /// The text of a vault file by vault-relative path (`nil` when it does not exist, and always
    /// for the fixture, which has no files). For checking the exact file format.
    let readFile: @Sendable (String) -> String?
    /// Names of the files (not folders) below a vault-relative folder, sorted; empty for the
    /// fixture and for a missing folder. For checking that files were trashed, not destroyed.
    let listFiles: @Sendable (String) -> [String]
    /// Writes a vault file from outside (vault only; the fixture ignores it).
    let writeFile: @Sendable (String, String) throws -> Void
    fileprivate let keepAlive: TempFolder?

    var courses: any CourseCatalog { env.courses }
    var notes: any NoteRepository { env.notes }
    var tasks: any TaskService { env.tasks }
    var capture: any CaptureService { env.capture }
    var inbox: any InboxService { env.inbox }
    var properties: any PropertyService { env.properties }
    var analysis: any NoteAnalysis { env.analysis }
    var graph: any GraphService { env.graph }
    var settings: any SettingsStore { env.settings }
    var semesters: any SemesterStore { env.semesters }
    var indexStatus: any IndexStatus { env.indexStatus }
    var grades: any GradeService { env.grades }
    var history: any HistoryService { env.history }
    var reminders: any ReminderService { env.reminders }
    var syllabus: any SyllabusService { env.syllabus }
    var exporter: any ExportService { env.export }
    var search: any SearchService { env.search }
    var changes: any ChangeSetStore { env.changes }
    var clock: any Clock { env.clock }

    static func make(_ kind: HarnessKind, clock: any Clock = FixedClock(),
                     watchInterval: TimeInterval = 0.05,
                     reminderCenter: any ReminderCenter = InMemoryReminderCenter()) async throws -> Harness {
        switch kind {
        case .fixture:
            let store = FixtureStore(world: Fixtures.week5, clock: clock)
            let env = AppEnvironment(
                clock: clock, courses: FixtureCourseCatalog(store: store), notes: FixtureNoteRepository(store: store),
                tasks: FixtureTaskService(store: store), capture: FixtureCaptureService(store: store),
                inbox: FixtureInboxService(store: store), properties: FixturePropertyService(store: store),
                analysis: FixtureNoteAnalysis(store: store), graph: FixtureGraphService(world: Fixtures.week5),
                courseWriter: FixtureCourseCatalogWriter(store: store), settings: FixtureSettingsStore(),
                semesters: FixtureSemesterStore(store: store), indexStatus: FixtureIndexStatus(),
                grades: FixtureGradeService(store: store),
                history: FixtureHistoryService(store: store, clock: clock),
                reminders: CatalogReminderService(courses: FixtureCourseCatalog(store: store), center: reminderCenter, clock: clock),
                syllabus: FixtureSyllabusService(store: store), export: FixtureExportService(store: store), search: FixtureSearchService(store: store),
                changes: FixtureChangeSetStore(store: store),
                shutdown: { store.catalogUpdates.finishAll(); store.noteChanges.finishAll(); store.taskChanges.finishAll() })
            return Harness(
                kind: kind, env: env, writer: FixtureCourseCatalogWriter(store: store),
                editNote: { id, text in try await store.simulateExternalEdit(id: id, text: text) },
                rawContent: { id in try await store.rawContent(id: id) },
                deleteNote: { id in try await store.simulateExternalDelete(id: id) },
                editCourseRoom: { id, room in try await store.simulateExternalCourseEdit(id: id) { $0.room = room } },
                readFile: { _ in nil }, listFiles: { _ in [] }, writeFile: { _, _ in },
                keepAlive: nil)
        case .vault:
            let folder = TempFolder()
            // The sample vault of the same fixtures (M5-09), written before the environment opens it.
            let store = try await VaultStore.open(root: folder.url, clock: clock, trash: PortableTrash(), createIfMissing: true)
            try await SampleVaultGenerator.generate(into: store, from: Fixtures.week5)
            let backend = try await VaultBackend.open(at: folder.url, clock: clock, watchInterval: watchInterval, trash: PortableTrash())
            let env = AppEnvironment(
                clock: clock, courses: VaultCourseCatalog(backend: backend), notes: VaultNoteRepository(backend: backend),
                tasks: VaultTaskService(backend: backend), capture: VaultCaptureService(backend: backend),
                inbox: VaultInboxService(backend: backend), properties: VaultPropertyService(backend: backend),
                analysis: VaultNoteAnalysis(backend: backend), graph: VaultGraphService(backend: backend),
                courseWriter: VaultCourseCatalogWriter(backend: backend),
                settings: VaultSettingsStore(store: await backend.store), semesters: VaultSemesterStore(backend: backend),
                indexStatus: VaultIndexStatus(backend: backend), grades: VaultGradeService(backend: backend),
                history: VaultHistoryService(backend: backend),
                reminders: CatalogReminderService(courses: VaultCourseCatalog(backend: backend), center: reminderCenter, clock: clock),
                syllabus: VaultSyllabusService(backend: backend), export: VaultExportService(backend: backend), search: VaultSearchService(backend: backend),
                changes: VaultChangeSetStore(backend: backend),
                shutdown: { await backend.shutdown() })
            let root = folder.url
            return Harness(
                kind: kind, env: env, writer: VaultCourseCatalogWriter(backend: backend),
                editNote: { id, text in
                    let file = try Self.file(ofNoteWithID: id, in: root)
                    let content = try String(contentsOf: file, encoding: .utf8)
                    let fm = Frontmatter.parse(content).frontmatter
                    try Data(((fm?.render() ?? "") + text).utf8).write(to: file)
                },
                rawContent: { id in try String(contentsOf: try Self.file(ofNoteWithID: id, in: root), encoding: .utf8) },
                deleteNote: { id in try FileManager.default.removeItem(at: try Self.file(ofNoteWithID: id, in: root)) },
                editCourseRoom: { id, room in
                    let file = try Self.file(ofNoteWithID: nil, courseID: id, in: root)
                    let content = try String(contentsOf: file, encoding: .utf8)
                    var (fm, body) = Frontmatter.parse(content)
                    fm?.set("room", .string(room))
                    try Data(((fm?.render() ?? "") + body).utf8).write(to: file)
                },
                readFile: { try? String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) },
                listFiles: { folder in
                    let url = root.appendingPathComponent(folder, isDirectory: true)
                    let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
                    return names.filter { !$0.hasPrefix(".") }.sorted()
                },
                writeFile: { path, text in
                    let url = root.appendingPathComponent(path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(text.utf8).write(to: url)
                },
                keepAlive: folder)
        }
    }

    func shutdown() async { await env.shutdown() }

    /// The markdown file whose frontmatter has `id: <noteID>` (or, for a course, its `_course.md`).
    private static func file(ofNoteWithID noteID: NoteID?, courseID: CourseID? = nil, in root: URL) throws -> URL {
        let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = en?.nextObject() as? URL {
            guard url.pathExtension == "md", let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let id = Frontmatter.parse(text).frontmatter?.string(for: "id")
            if let noteID, id == noteID, url.lastPathComponent != "_course.md" { return url }
            if let courseID, id == courseID, url.lastPathComponent == "_course.md" { return url }
        }
        throw MarginError.notFound("No file for \(noteID ?? courseID ?? "?")")
    }
}

/// Runs `body` against a fresh harness and always shuts it down.
func withHarness(_ kind: HarnessKind, clock: any Clock = FixedClock(), watchInterval: TimeInterval = 0.05,
                 reminderCenter: any ReminderCenter = InMemoryReminderCenter(),
                 _ body: (Harness) async throws -> Void) async throws {
    let harness = try await Harness.make(kind, clock: clock, watchInterval: watchInterval, reminderCenter: reminderCenter)
    do { try await body(harness) } catch {
        await harness.shutdown()
        throw error
    }
    await harness.shutdown()
}

/// The first element of `stream` that satisfies `predicate`, or `nil` after `timeout` seconds.
func next<T: Sendable>(from stream: AsyncStream<T>, timeout: TimeInterval = 30,
                       where predicate: @escaping @Sendable (T) -> Bool = { _ in true }) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            for await element in stream where predicate(element) { return element }
            return nil
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

/// Elements of `stream` collected until one satisfies `predicate` (or the timeout passes).
func collect<T: Sendable>(from stream: AsyncStream<T>, timeout: TimeInterval = 30,
                          until predicate: @escaping @Sendable (T) -> Bool) async -> [T] {
    await withTaskGroup(of: [T].self) { group in
        group.addTask {
            var seen: [T] = []
            for await element in stream {
                seen.append(element)
                if predicate(element) { break }
            }
            return seen
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return []
        }
        // Whichever finishes first: the collector (found) or the timer (empty).
        var result: [T] = []
        for await r in group { result = r; break }
        group.cancelAll()
        return result
    }
}

let testActor = Actor.agent(identity: "study-helper", client: "conformance", session: "s-1", purpose: "test")

/// A clock tests can move forward (retention is measured against the `Clock`).
final class MutableClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    let timeZone: TimeZone

    init(start: Date = FixedClock().now, timeZone: TimeZone = FixedClock.defaultTimeZone) {
        current = start; self.timeZone = timeZone
    }

    var now: Date { lock.withLock { current } }
    func advance(bySeconds seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
