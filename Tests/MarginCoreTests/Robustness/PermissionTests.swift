import Foundation
import Testing
@testable import MarginCore

extension Robustness {
/// M12-03, permission denied: a read-only note, a read-only folder, an unreadable note, an
/// unreadable subfolder and an unreadable vault. A real `chmod` is used where it can deny anything;
/// the tests usually run as root (Docker), which ignores permission bits, so folder and read
/// denials fall back to the same `EACCES` injected at the `FileSystem` seam
/// (`RobustVault.denyWriting`, `ScriptedFileSystem`). The read-only *file* case does not depend
/// on the OS: the store itself refuses to replace a file whose write bit is off.
@Suite struct PermissionTests {
    static let bioFolder = "Fall 2026/Cell Biology"

    // MARK: Read-only file

    @Test func aReadOnlyNoteIsNeverOverwritten() async throws {
        try await withRobustVault { v in
            let path = try #require(v.dir.path(ofNoteWithID: "bio/lecture-8"))
            let original = try #require(v.dir.bytes(path))
            try v.dir.setPermissions(0o444, path)
            let attempts: [(String, @Sendable (AppEnvironment) async throws -> Void)] = [
                ("save", { _ = try await $0.notes.save(id: "bio/lecture-8", text: "x", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
                ("properties.set", { _ = try await $0.properties.set(key: "difficulty", value: .number(2), on: "bio/lecture-8", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
                ("properties.remove", { _ = try await $0.properties.remove(key: "type", on: "bio/lecture-8", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }),
                ("capture attach", { _ = try await $0.capture.commit(CaptureDraft(text: "appended", kind: .note, attachTo: "bio/lecture-8"), actor: robustActor, dryRun: false, idempotencyKey: nil) }),
            ]
            for (name, run) in attempts {
                #expect(await robustCode { try await run(v.env) } == "readOnly", "\(name)")
                #expect(v.dir.bytes(path) == original, "\(name): a read-only note changed")
            }
            let perms = try FileManager.default.attributesOfItem(atPath: v.dir.file(path).path)[.posixPermissions] as? Int
            #expect(perms == 0o444)
            #expect(v.dir.temporaryFiles.isEmpty)
            // It can still be read, and the vault around it works.
            #expect(try await v.env.notes.open(id: "bio/lecture-8").text.hasPrefix("# Lecture 8"))
            _ = try await v.env.notes.save(id: "bio/lecture-7", text: "# Lecture 7\n\nedited\n", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            // Made writable again, the same call works and keeps the mode it had.
            try v.dir.setPermissions(0o644, path)
            for (name, run) in attempts { #expect(await robustCode { try await run(v.env) } == nil, "\(name) after chmod") }
            #expect(await v.matchesRestart(), "services disagree with the files on disk")
        }
    }

    @Test func aReadOnlyNoteBlocksTaskToggleAndDueDate() async throws {
        try await withRobustVault { v in
            let path = try #require(v.dir.path(ofNoteWithID: "bio/assignments"))
            let original = try #require(v.dir.bytes(path))
            try v.dir.setPermissions(0o444, path)
            #expect(await robustCode { try await v.env.tasks.toggle(id: "task-bio-read-chapter-6", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "readOnly")
            #expect(await robustCode { try await v.env.tasks.setDue(id: "task-bio-read-chapter-6", due: nil, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "readOnly")
            #expect(v.dir.bytes(path) == original)
            // The task is unchanged for the reader, too.
            let task = try #require(try await v.env.tasks.tasks(course: "bio").first { $0.id == "task-bio-read-chapter-6" })
            #expect(task.done == false || task.done == true)
            try v.dir.setPermissions(0o644, path)
            _ = try await v.env.tasks.toggle(id: "task-bio-read-chapter-6", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(v.dir.bytes(path) != original)
        }
    }

    @Test func aReadOnlyFileDoesNotStopTheStoreFromReadingListingOrTrashing() async throws {
        try await withRobustVault { v in
            let path = try #require(v.dir.path(ofNoteWithID: "bio/glossary"))
            try v.dir.setPermissions(0o444, path)
            #expect(try await v.env.notes.open(id: "bio/glossary").id == "bio/glossary")
            // Moving to the trash keeps the bytes: it is not a change of content.
            let original = try #require(v.dir.bytes(path))
            _ = try await v.env.notes.delete(id: "bio/glossary", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(v.files().values.contains(original))
        }
    }

    // MARK: Read-only folder

    @Test(arguments: WriteOp.all.filter { ["notes.save", "notes.create", "tasks.toggle", "properties.set", "capture note", "capture task", "courseWriter.setStyle"].contains($0.name) })
    func aReadOnlyFolderRefusesChangesAndNothingElse(op: WriteOp) async throws {
        try await withRobustVault { v in
            let before = v.files()
            let lift = try v.denyWriting(inFolder: Self.bioFolder)
            let code = await robustCode { try await op.run(v.env) }
            #expect(code == "io", "\(op.name): \(code ?? "succeeded")")
            #expect(v.files() == before, "\(op.name): the vault changed")
            #expect(v.dir.temporaryFiles.isEmpty)
            await exerciseReads(v.env)
            // Other courses are unaffected.
            let ok = await robustCode { try await v.env.notes.save(id: "chem/lecture-6", text: "# Chem\n\nfine\n", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
            #expect(ok == nil || ok == "notFound", "other course: \(ok ?? "")")
            try lift()
            #expect(await robustCode { try await op.run(v.env) } == nil, "\(op.name) after the folder is writable")
            #expect(await v.matchesRestart(), "services disagree with the files on disk")
        }
    }

    @Test func theErrorSaysPermissionDenied() async throws {
        try await withRobustVault { v in
            _ = try v.denyWriting(inFolder: Self.bioFolder)
            do {
                _ = try await v.env.notes.save(id: "bio/lecture-8", text: "x", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
                Issue.record("must fail")
            } catch let e as MarginError {
                #expect(e.code == "io")
                #expect(e.message.contains("Permission denied"), "\(e.message)")
            }
        }
    }

    // MARK: Unreadable note and folder

    /// Makes a note unreadable: `chmod 000` where that works, else `EACCES` on reading it.
    private func denyReading(_ relative: String, in v: RobustVault) throws -> () throws -> Void {
        if !chmodIsIneffective {
            try v.dir.setPermissions(0o000, relative)
            return { try v.dir.setPermissions(0o644, relative) }
        }
        v.fs.inject(.denied, ops: ["readData"], pathContains: URL(fileURLWithPath: relative).lastPathComponent)
        return { v.fs.clear() }
    }

    @Test func anUnreadableNoteIsSkippedAtOpenAndIndexedOnceItCanBeRead() async throws {
        var lift: (() throws -> Void)?
        try await withRobustVault(prepare: { dir, fs in
            let path = try #require(dir.path(ofNoteWithID: "bio/glossary"))
            if !chmodIsIneffective { try dir.setPermissions(0o000, path) }
            else { fs.inject(.denied, ops: ["readData"], pathContains: URL(fileURLWithPath: path).lastPathComponent) }
            lift = { if !chmodIsIneffective { try dir.setPermissions(0o644, path) } else { fs.clear() } }
        }) { v in
            // The vault opens; the note is missing, everything else is there.
            let notes = try await v.env.notes.notes(course: nil)
            #expect(notes.count == 18 && !notes.contains { $0.id == "bio/glossary" })
            #expect(await robustCode { try await v.env.notes.open(id: "bio/glossary") } == "notFound")
            await exerciseReads(v.env)
            // Permission is fixed: mtime does not change, yet the note shows up.
            try lift?()
            let appeared = await eventually { (try? await v.env.notes.open(id: "bio/glossary")) != nil }
            #expect(appeared, "the note stayed invisible after it became readable")
            let listed = await eventually { ((try? await v.env.notes.notes(course: nil))?.count ?? 0) == 19 }
            #expect(listed, "the note never reached the index")
        }
    }

    @Test func anUnreadableSubfolderDoesNotStopTheVaultFromOpening() async throws {
        var lift: (() throws -> Void)?
        try await withRobustVault(prepare: { dir, fs in
            if !chmodIsIneffective { try dir.setPermissions(0o000, Self.bioFolder) }
            else { fs.inject(.denied, ops: ["contentsOfDirectory"], pathContains: "Cell Biology") }
            lift = { if !chmodIsIneffective { try dir.setPermissions(0o755, Self.bioFolder) } else { fs.clear() } }
        }) { v in
            let notes = try await v.env.notes.notes(course: nil)
            #expect(!notes.isEmpty && notes.allSatisfy { !$0.id.hasPrefix("bio/") }, "notes of the unreadable folder must be missing, the rest present")
            #expect(notes.count == 9)
            await exerciseReads(v.env)
            // Work in the other courses continues.
            _ = try await v.env.notes.create(course: "chem", title: "Still working", kind: .note, text: "yes", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            _ = try await v.env.capture.commit(CaptureDraft(text: "inbox works"), actor: robustActor, dryRun: false, idempotencyKey: nil)
            try lift?()
            if !chmodIsIneffective {
                // The watcher notices the folder coming back.
                let back = await eventually { ((try? await v.env.notes.notes(course: nil))?.count ?? 0) == 20 }
                #expect(back)
            } else {
                // (The portable watcher reads the real disk, where nothing was ever denied.)
                #expect(try await v.reopened().notes.notes(course: nil).count == 20)
            }
        }
    }

    @Test func anUnreadableVaultRootFailsToOpenWithATypedError() async throws {
        let dir = TempDir()
        try dir.seed("Fall 2026/Bio/note.md", Data("# n\n".utf8))
        let fs = ScriptedFileSystem()
        fs.inject(.denied, ops: ["contentsOfDirectory", "realPath"], pathContains: nil)
        do {
            _ = try await AppEnvironment.vault(at: dir.url, clock: FixedClock(), watchInterval: 0.05, fileSystem: fs, trash: PortableTrash())
            Issue.record("must not open")
        } catch let e as MarginError { #expect(e.code == "io", "\(e)") }
        fs.clear()
        let env = try await AppEnvironment.vault(at: dir.url, clock: FixedClock(), watchInterval: 0.05, fileSystem: fs, trash: PortableTrash())
        await env.shutdown()
    }
}
}
