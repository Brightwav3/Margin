import Foundation
import Testing
@testable import MarginCore

/// A `FileSystem` that fails on demand, the way a real disk does: `ENOSPC` while writing, `EACCES`
/// on a folder, `EIO` when a volume disappears. Unlike `FaultInjectingFileSystem` (fail the n-th
/// call) a rule here names the operations and paths to fail and stays in force until `clear()`, so
/// a test can show that the services work again once the fault is gone.
final class ScriptedFileSystem: FileSystem, @unchecked Sendable {
    /// The errno-style failures the tests use.
    enum Failure: Sendable {
        case noSpace, denied, readOnlyVolume, io, notFound

        var code: Int32 {
            switch self {
            case .noSpace: ENOSPC
            case .denied: EACCES
            case .readOnlyVolume: EROFS
            case .io: EIO
            case .notFound: ENOENT
            }
        }

        func error(_ op: String, _ url: URL) -> FileSystemError {
            let text = "\(op) \(url.lastPathComponent): \(String(cString: strerror(code))) (errno \(code))"
            return self == .notFound ? .notFound(text) : .failed(text)
        }
    }

    struct Rule: Sendable {
        /// `FileSystem` method names (`createFile`, `sync`, `replaceItem`, …).
        var ops: Set<String>
        /// Only paths containing this text (`nil`: every path).
        var pathContains: String?
        var failure: Failure
        /// `createFile` only: leave half of the bytes behind before failing (a disk that fills up mid-write).
        var partialWrite = false
        /// Execute the call, then report the failure (the change happened, the caller is told it did not).
        var afterExecuting = false
        /// Let this many matching calls through before failing.
        var skip = 0
    }

    private let base: any FileSystem
    private let lock = NSLock()
    private var rules: [Rule] = []
    private var matched: [Int: Int] = [:]
    private var injected = 0
    private var hook: (@Sendable (String, URL) -> Void)?

    init(base: any FileSystem = POSIXFileSystem()) { self.base = base }

    /// How many calls failed because of a rule.
    var injectedCount: Int { lock.withLock { injected } }

    func inject(_ rule: Rule) { lock.withLock { rules.append(rule) } }

    func inject(_ failure: Failure, ops: Set<String>, pathContains: String? = nil, partialWrite: Bool = false,
                afterExecuting: Bool = false, skip: Int = 0) {
        inject(Rule(ops: ops, pathContains: pathContains, failure: failure, partialWrite: partialWrite,
                    afterExecuting: afterExecuting, skip: skip))
    }

    /// The fault is gone (space freed, permissions fixed, volume back).
    func clear() { lock.withLock { rules = []; matched = [:] } }

    /// Runs `body` before every call (with its name and path); used to change the disk "behind the store's back".
    func onCall(_ body: (@Sendable (String, URL) -> Void)?) { lock.withLock { hook = body } }

    private func gate(_ op: String, _ url: URL) -> Rule? {
        let (hookCopy, hit): ((@Sendable (String, URL) -> Void)?, Rule?) = lock.withLock {
            var hit: Rule?
            for (i, r) in rules.enumerated() where r.ops.contains(op) && (r.pathContains.map { url.path.contains($0) } ?? true) {
                let seen = matched[i, default: 0]
                matched[i] = seen + 1
                if seen >= r.skip { hit = r; break }
            }
            if hit != nil { injected += 1 }
            return (hook, hit)
        }
        hookCopy?(op, url)
        return hit
    }

    private func step<T>(_ op: String, _ url: URL, partial: (() throws -> Void)? = nil, _ body: () throws -> T) throws -> T {
        guard let rule = gate(op, url) else { return try body() }
        if rule.afterExecuting { _ = try body() } else if rule.partialWrite { try partial?() }
        throw rule.failure.error(op, url)
    }

    func attributes(at url: URL) throws -> FileAttributes? { try step("attributes", url) { try base.attributes(at: url) } }
    func realPath(_ url: URL) throws -> URL { try step("realPath", url) { try base.realPath(url) } }
    func readData(at url: URL) throws -> Data { try step("readData", url) { try base.readData(at: url) } }
    func createDirectories(at url: URL) throws { try step("createDirectories", url) { try base.createDirectories(at: url) } }
    func createFile(at url: URL, data: Data, permissions: UInt16?) throws {
        try step("createFile", url, partial: {
            try self.base.createFile(at: url, data: Data(data.prefix(data.count / 2)), permissions: permissions)
        }) { try base.createFile(at: url, data: data, permissions: permissions) }
    }
    func sync(fileAt url: URL) throws { try step("sync", url) { try base.sync(fileAt: url) } }
    func syncDirectory(at url: URL) throws { try step("syncDirectory", url) { try base.syncDirectory(at: url) } }
    func replaceItem(at destination: URL, withItemAt source: URL) throws {
        try step("replaceItem", destination) { try base.replaceItem(at: destination, withItemAt: source) }
    }
    func moveItemNoReplace(from source: URL, to destination: URL) throws {
        try step("moveItemNoReplace", destination) { try base.moveItemNoReplace(from: source, to: destination) }
    }
    func removeFile(at url: URL) throws { try step("removeFile", url) { try base.removeFile(at: url) } }
    func contentsOfDirectory(at url: URL) throws -> [DirectoryEntry] { try step("contentsOfDirectory", url) { try base.contentsOfDirectory(at: url) } }
}

/// Deterministic random numbers (SplitMix64) for the tests below.
struct RobustRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// `true` when `chmod` cannot deny anything here (root, as in the Docker test container).
let chmodIsIneffective: Bool = geteuid() == 0

/// The sample vault (`Fixtures.week5`) opened through `AppEnvironment.vault` on a `ScriptedFileSystem`.
struct RobustVault: @unchecked Sendable {
    let dir: TempDir
    let fs: ScriptedFileSystem
    let env: AppEnvironment
    let clock: any Clock

    static func make(watchInterval: TimeInterval = 0.05, populate: Bool = true, clock: any Clock = FixedClock(),
                     seed: (TempDir) throws -> Void = { _ in }) async throws -> RobustVault {
        let dir = TempDir()
        if populate {
            let store = try await VaultStore.open(root: dir.url, clock: clock, createIfMissing: true)
            try await SampleVaultGenerator.generate(into: store, from: Fixtures.week5)
        }
        try seed(dir)
        let fs = ScriptedFileSystem()
        let env = try await AppEnvironment.vault(at: dir.url, clock: clock, watchInterval: watchInterval, fileSystem: fs)
        return RobustVault(dir: dir, fs: fs, env: env, clock: clock)
    }

    /// A second, fault-free environment over the same folder: what the app would show after a restart.
    func reopened() async throws -> AppEnvironment {
        try await AppEnvironment.vault(at: dir.url, clock: clock, watchInterval: 0.05, fileSystem: POSIXFileSystem())
    }

    func shutdown() async { await env.shutdown() }

    /// Every file in the vault (relative path -> bytes) without the store's own temporary files.
    func files() -> [String: Data] {
        dir.snapshot().filter { !VaultStore.isTemporaryName(String($0.key.split(separator: "/").last ?? "")) }
    }
}

/// Runs `body` against a fresh vault and always shuts the environment down.
func withRobustVault(watchInterval: TimeInterval = 0.05, populate: Bool = true,
                     seed: (TempDir) throws -> Void = { _ in },
                     _ body: (RobustVault) async throws -> Void) async throws {
    let v = try await RobustVault.make(watchInterval: watchInterval, populate: populate, seed: seed)
    do { try await body(v) } catch {
        await v.shutdown()
        throw error
    }
    await v.shutdown()
}

/// Polls `body` until it returns true (the watcher needs a few scans to notice outside changes).
func eventually(timeout: TimeInterval = 20, _ body: () async throws -> Bool) async rethrows -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if try await body() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

/// The error code of `body` (`nil` when it succeeds, `"other"` for an error that is not a `MarginError`).
func robustCode<T>(_ body: () async throws -> T) async -> String? {
    do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other" }
}

let robustActor = Actor.agent(identity: "study-helper", client: "robustness", session: "s-1", purpose: "test")

/// One write through a service, by name. Together they cover every service that writes.
struct WriteOp: Sendable, CustomTestStringConvertible {
    var name: String
    var run: @Sendable (AppEnvironment) async throws -> Void
    var testDescription: String { name }

    private static func plain(_ body: @escaping @Sendable (AppEnvironment) async throws -> ChangeSet) -> @Sendable (AppEnvironment) async throws -> Void {
        { env in _ = try await body(env) }
    }

    static let all: [WriteOp] = [
        WriteOp(name: "notes.save", run: plain { try await $0.notes.save(id: "bio/lecture-8", text: "# Lecture 8 — edited\n\nNew body ^t-abcd\n", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "notes.create", run: plain { try await $0.notes.create(course: "bio", title: "Robust note", kind: .study, text: "Body", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "notes.move", run: plain { try await $0.notes.move(id: "bio/glossary", toCourse: "chem", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "notes.delete", run: plain { try await $0.notes.delete(id: "bio/glossary", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "tasks.toggle", run: plain { try await $0.tasks.toggle(id: "task-bio-read-chapter-6", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "tasks.setDue", run: plain { try await $0.tasks.setDue(id: "task-bio-read-chapter-6", due: LocalDate(year: 2026, month: 10, day: 9), actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "capture inbox", run: plain { try await $0.capture.commit(CaptureDraft(text: "Loose thought"), actor: robustActor, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "capture task", run: plain { try await $0.capture.commit(CaptureDraft(text: "Read chapter 9", course: "bio", kind: .task), actor: robustActor, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "capture note", run: plain { try await $0.capture.commit(CaptureDraft(text: "An idea for the lab", course: "bio", kind: .note), actor: robustActor, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "inbox.triage", run: { env in
            let item = try #require(try await env.inbox.items().first)
            _ = try await env.inbox.triage(item: item.id, course: "bio", when: nil, kind: nil, actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        }),
        WriteOp(name: "inbox.delete", run: { env in
            let item = try #require(try await env.inbox.items().first)
            _ = try await env.inbox.delete(item: item.id, actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        }),
        WriteOp(name: "properties.set", run: plain { try await $0.properties.set(key: "difficulty", value: .number(3), on: "bio/lecture-8", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "properties.remove", run: plain { try await $0.properties.remove(key: "type", on: "bio/lecture-8", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "courseWriter.create", run: plain { try await $0.courseWriter.create(NewCourse(name: "Statistics", semester: "fall-2026", code: "STA 101", professor: "Dr. Novak", room: "Hall C"), actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "courseWriter.rename", run: plain { try await $0.courseWriter.rename(id: "bio", to: "Biology Two", renameFolder: true, actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "courseWriter.setStyle", run: plain { try await $0.courseWriter.setStyle(id: "bio", icon: "science", color: "econ", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "courseWriter.setArchived", run: plain { try await $0.courseWriter.setArchived(semester: "fall-2026", true, actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
        WriteOp(name: "courseWriter.override", run: plain { try await $0.courseWriter.override(session: SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: LocalDate(year: 2026, month: 9, day: 29)!, cancelled: true), actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
    ]
}

/// Everything a screen reads, gathered in one value so two environments can be compared.
struct ReadModel: Equatable, Sendable {
    var courseNames: [String]
    var notes: [NoteSummary]
    var today: [String]
    var upcoming: [String]
    var courseTasks: [String: [String]]
    var inbox: [String]
}

func readModel(_ env: AppEnvironment) async throws -> ReadModel {
    let courses = try await env.courses.courses(query: nil)
    var perCourse: [String: [String]] = [:]
    for c in courses { perCourse[c.id] = try await env.tasks.tasks(course: c.id).map { "\($0.id)|\($0.done)|\($0.text)|\($0.due?.iso ?? "-")" } }
    return ReadModel(
        courseNames: courses.map(\.name), notes: try await env.notes.notes(course: nil),
        today: try await env.tasks.today().map(\.id), upcoming: try await env.tasks.upcoming().map(\.id),
        courseTasks: perCourse, inbox: try await env.inbox.items().map(\.id))
}

/// Touches every read path of every service; each must answer (or fail with a `MarginError`), never crash.
func exerciseReads(_ env: AppEnvironment) async {
    _ = try? await env.courses.semesters()
    _ = try? await env.courses.courses(query: nil)
    _ = try? await env.courses.sessions(week: 5)
    let notes = (try? await env.notes.notes(course: nil)) ?? []
    for n in notes {
        _ = try? await env.notes.open(id: n.id)
        _ = try? await env.analysis.outline(id: n.id)
        _ = try? await env.analysis.backlinks(id: n.id)
        _ = try? await env.analysis.outgoing(id: n.id)
        _ = try? await env.analysis.stats(id: n.id, text: nil)
        _ = try? await env.analysis.properties(id: n.id)
        _ = try? await env.search.excerpt(note: n.id)
    }
    _ = try? await env.tasks.today()
    _ = try? await env.tasks.upcoming()
    _ = try? await env.inbox.items()
    _ = try? await env.properties.types()
    _ = try? await env.graph.graph(scope: .all, filter: .none)
    _ = try? await env.search.search(query: "the")
    _ = try? await env.search.suggestLinks(prefix: "a")
}
