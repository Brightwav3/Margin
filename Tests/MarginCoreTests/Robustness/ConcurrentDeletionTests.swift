import Foundation
import Testing
@testable import MarginCore

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func fire() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
    var fired: Bool { lock.withLock { done } }
}

extension Robustness {
/// M12-03, concurrent external deletion: another program (Finder, a sync client, `git checkout`)
/// removes, replaces or moves a note or its folder at the worst moment of a service write. The
/// timing is exact through `ScriptedFileSystem.onCall`, plus a seeded random storm of writers
/// against an external chaos task.
///
/// Required: a typed `MarginError` or success (never a crash, a partial file or a temp file left),
/// files the operation did not target intact, and services that agree with the disk afterwards.
@Suite struct ConcurrentDeletionTests {
    enum Disturbance: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case deleteFile, deleteFolder, replaceWithOtherContent
        var testDescription: String { rawValue }
    }

    /// A write on one existing file, with the id of the note (or `nil` for an inbox file) it targets.
    struct Target: Sendable, CustomTestStringConvertible {
        var op: String
        var noteID: String?
        var testDescription: String { op }
        static let all: [Target] = [
            Target(op: "notes.save", noteID: "bio/lecture-8"),
            Target(op: "properties.set", noteID: "bio/lecture-8"),
            Target(op: "properties.remove", noteID: "bio/lecture-8"),
            Target(op: "tasks.toggle", noteID: "bio/assignments"),
            Target(op: "tasks.setDue", noteID: "bio/assignments"),
            Target(op: "notes.move", noteID: "bio/glossary"),
            Target(op: "notes.delete", noteID: "bio/glossary"),
            Target(op: "inbox.delete", noteID: nil),
            Target(op: "inbox.triage", noteID: nil),
        ]
    }

    static let stages = ["createFile", "sync", "replaceItem", "moveItemNoReplace", "syncDirectory"]

    @Test(arguments: Target.all, Disturbance.allCases)
    func aFileDisturbedMidWriteEndsCleanly(target: Target, disturbance: Disturbance) async throws {
        for stage in Self.stages {
            try await withRobustVault { v in
                let path: String
                if let id = target.noteID { path = try #require(v.dir.path(ofNoteWithID: id)) }
                else { path = try #require(v.files().keys.first { $0.hasPrefix("_inbox/") }) }
                let before = v.files()
                let victim = v.dir.file(path)
                let once = Once()
                let other = Data("---\nid: other\n---\n# Replaced from outside\n".utf8)
                v.fs.onCall { name, _ in
                    guard name == stage, once.fire() else { return }
                    switch disturbance {
                    case .deleteFile: try? FileManager.default.removeItem(at: victim)
                    case .deleteFolder: try? FileManager.default.removeItem(at: victim.deletingLastPathComponent())
                    case .replaceWithOtherContent: try? other.write(to: victim)
                    }
                }
                let op = try #require(WriteOp.all.first { $0.name == target.op })
                let code = await robustCode { try await op.run(v.env) }
                v.fs.onCall(nil)
                let label = "\(target.op) / \(disturbance) before \(stage)"
                #expect(code == nil || ["conflict", "notFound", "io", "invalid"].contains(code ?? ""), "\(label): \(code ?? "")")
                #expect(v.dir.temporaryFiles.isEmpty, "\(label): temp files left")
                if !once.fired { return }   // this operation has no such step (a trash never fsyncs a temp file)

                // Everything the operation did not target is intact (or moved along with its folder).
                let after = v.files()
                let untouched = before.filter { key, _ in
                    key != path && !(disturbance == .deleteFolder && key.hasPrefix(victim.deletingLastPathComponent().lastPathComponent + "/"))
                        && !(disturbance == .deleteFolder && key.contains(victim.deletingLastPathComponent().lastPathComponent))
                }
                let multi = ["inbox.triage", "notes.move"].contains(target.op)
                let lost = FullDiskTests.lost(untouched, in: after, allowModified: multi)
                #expect(lost.isEmpty, "\(label): other files lost or changed: \(lost)")

                // The services follow the disk, and the vault keeps working.
                #expect(await v.matchesRestart(), "\(label): services disagree with the files on disk")
                let again = await robustCode { try await v.env.notes.create(course: "chem", title: "After the storm", kind: .note, text: "ok", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
                #expect(again == nil, "\(label): vault unusable afterwards: \(again ?? "")")
            }
        }
    }

    @Test func aWriteNeverSilentlyDiscardsAnExternalReplacement() async throws {
        // With `baseVersion` the caller says which version it edited. Another program replaced the
        // file after the read and before the rename: the write must fail with a conflict or, when it
        // wins the race, leave the new content; the outside content must survive somewhere or the
        // caller must have been told.
        try await withRobustVault { v in
            let path = try #require(v.dir.path(ofNoteWithID: "bio/lecture-8"))
            let note = try await v.env.notes.open(id: "bio/lecture-8")
            let outside = Data("---\nid: bio/lecture-8\n---\n# Edited by another program\n".utf8)
            try outside.write(to: v.dir.file(path))
            let code = await robustCode { try await v.env.notes.save(id: "bio/lecture-8", text: "# mine\n", actor: robustActor, baseVersion: note.version, dryRun: false, idempotencyKey: nil) }
            #expect(code == "conflict")
            #expect(v.dir.bytes(path) == outside, "the outside edit was overwritten despite the stale baseVersion")
        }
    }

    // MARK: Storm

    @Test func writersAgainstAnExternalChaosTaskNeverCorruptAnything() async throws {
        try await withRobustVault { v in
            let files = ["bio/lecture-8", "bio/assignments", "bio/glossary", "bio/lecture-7"].compactMap { id in v.dir.path(ofNoteWithID: id).map { (id, $0) } }
            #expect(files.count == 4)
            let originals = Dictionary(uniqueKeysWithValues: files.map { ($0.1, v.dir.bytes($0.1) ?? Data()) })
            let untouchedBefore = v.files().filter { originals[$0.key] == nil }
            let deadline = Date().addingTimeInterval(4)
            let dir = v.dir
            let env = v.env

            let results = await withTaskGroup(of: [String].self) { group -> [String] in
                for worker in 0..<5 {
                    group.addTask {
                        var rng = RobustRNG(seed: UInt64(1000 + worker))
                        var codes: [String] = []
                        while Date() < deadline {
                            let (id, _) = files[Int(rng.next() % UInt64(files.count))]
                            let n = Int(rng.next() % 6)
                            let code: String?
                            switch n {
                            case 0: code = await robustCode { try await env.notes.save(id: id, text: "# Worker \(worker)\n\nround \(rng.next() % 1000)\n", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
                            case 1: code = await robustCode { try await env.properties.set(key: "rank", value: .number(Double(rng.next() % 9)), on: id, actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
                            case 2: code = await robustCode { try await env.tasks.toggle(id: "task-bio-read-chapter-6", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
                            case 3: code = await robustCode { try await env.capture.commit(CaptureDraft(text: "storm \(rng.next() % 100)", kind: .note, attachTo: id), actor: robustActor, dryRun: false, idempotencyKey: nil) }
                            case 4: code = await robustCode { try await env.notes.open(id: id) }
                            default: code = await robustCode { try await env.tasks.upcoming() }
                            }
                            if let code { codes.append(code) }
                            await Task.yield()
                        }
                        return codes
                    }
                }
                group.addTask {
                    var rng = RobustRNG(seed: 99)
                    while Date() < deadline {
                        let (_, path) = files[Int(rng.next() % UInt64(files.count))]
                        let url = dir.file(path)
                        switch rng.next() % 5 {
                        case 0: try? FileManager.default.removeItem(at: url)
                        case 1: try? (originals[path] ?? Data()).write(to: url)
                        case 2: try? Data("---\nid: chaos\n---\n# chaos \(rng.next() % 100)\n".utf8).write(to: url)
                        case 3:
                            let away = url.appendingPathExtension("away")
                            if (try? FileManager.default.moveItem(at: url, to: away)) != nil {
                                try? await Task.sleep(nanoseconds: 2_000_000)
                                try? FileManager.default.moveItem(at: away, to: url)
                            }
                        default: try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("nothing"))
                        }
                        try? await Task.sleep(nanoseconds: UInt64(1_000_000 + rng.next() % 8_000_000))
                    }
                    return []
                }
                var all: [String] = []
                for await codes in group { all += codes }
                return all
            }

            let bad = results.filter { !["conflict", "notFound", "io", "invalid", "readOnly"].contains($0) }
            #expect(bad.isEmpty, "unexpected error kinds: \(Set(bad))")
            print("storm: \(results.count) typed failures, kinds \(Dictionary(grouping: results, by: { $0 }).mapValues(\.count))")

            // Restore what the chaos left missing, then everything must settle.
            for (path, bytes) in originals where !dir.exists(path) { try dir.seed(path, bytes) }
            for leftover in FileManager.default.subpaths(atPath: dir.url.path) ?? [] where leftover.hasSuffix(".away") {
                try? FileManager.default.removeItem(at: dir.file(leftover))
            }
            #expect(dir.temporaryFiles.isEmpty, "temp files: \(dir.temporaryFiles)")
            for (path, data) in v.files() where path.hasSuffix(".md") {
                #expect(String(validating: data, as: UTF8.self) != nil, "\(path) is not valid UTF-8")
                #expect(!data.isEmpty || originals[path] == nil, "\(path) is empty")
            }
            #expect(v.files().filter { originals[$0.key] == nil && untouchedBefore[$0.key] != nil }.allSatisfy { untouchedBefore[$0.key] == $0.value || $0.key.hasPrefix("_inbox") || $0.key.hasSuffix("Tasks.md") || $0.key.contains(".margin/") }, "an untouched file changed")
            #expect(await v.matchesRestart(timeout: 40), "services disagree with the files on disk after the storm")
            #expect(await robustCode { try await v.env.notes.save(id: "bio/lecture-8", text: "# Calm again\n", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == nil)
        }
    }
}
}
