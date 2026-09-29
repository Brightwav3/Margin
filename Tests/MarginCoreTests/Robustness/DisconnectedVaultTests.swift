import Foundation
import Testing
@testable import MarginCore

/// Collects what a stream reports until the test asks.
private actor BatchLog<T: Sendable> {
    private(set) var items: [T] = []
    func add(_ item: T) { items.append(item) }
}

extension Robustness {
/// M12-03, disconnected vault: the vault folder disappears while the app runs (unplugged drive,
/// unmounted share, moved or deleted folder) and comes back. Disappearing is simulated by renaming
/// the folder (an unmounted volume looks the same to the app: the path stops existing) and by
/// making every call fail with `EIO` (a stale network mount).
///
/// Required: no crash, no notes reported deleted, no vault re-created at the old path, typed
/// `.notFound`/`.io` from everything that needs the disk, and full recovery when it is back,
/// including changes made while it was away.
@Suite struct DisconnectedVaultTests {
    /// Moves the vault folder away (`false`) or back (`true`) like unmounting and mounting a volume.
    private func mount(_ v: RobustVault, _ present: Bool) throws {
        let away = v.dir.url.deletingLastPathComponent().appendingPathComponent(v.dir.url.lastPathComponent + "-away")
        if present { try FileManager.default.moveItem(at: away, to: v.dir.url) } else { try FileManager.default.moveItem(at: v.dir.url, to: away) }
    }

    private func awayURL(_ v: RobustVault) -> URL {
        v.dir.url.deletingLastPathComponent().appendingPathComponent(v.dir.url.lastPathComponent + "-away")
    }

    @Test func removingTheFolderNeverCrashesAndReportsTypedErrors() async throws {
        try await withRobustVault { v in
            let model = try await readModel(v.env)
            try mount(v, false)
            defer { try? FileManager.default.removeItem(at: awayURL(v)) }

            await exerciseReads(v.env)   // must answer or throw a MarginError, never trap

            // Reads that need the disk fail with a typed error; reads the index can answer still do.
            let openCode = await robustCode { try await v.env.notes.open(id: "bio/lecture-8") }
            #expect(openCode == "notFound" || openCode == "io", "open: \(openCode ?? "succeeded")")
            let inboxCode = await robustCode { try await v.env.inbox.items() }
            #expect(inboxCode == "notFound" || inboxCode == "io", "inbox: \(inboxCode ?? "an empty inbox")")
            #expect(try await v.env.notes.notes(course: nil) == model.notes)

            // Every write is refused: nothing is created, nowhere.
            for op in WriteOp.all {
                let code = await robustCode { try await op.run(v.env) }
                #expect(code == "notFound" || code == "io", "\(op.name): \(code ?? "succeeded while the vault is gone")")
            }
            #expect(!FileManager.default.fileExists(atPath: v.dir.url.path), "a write re-created the vault folder at its old place")
        }
    }

    @Test func theWatcherDoesNotReportEverythingDeletedWhenTheFolderIsGone() async throws {
        try await withRobustVault { v in
            let changes = BatchLog<[NoteChange]>()
            let stream = v.env.notes.externalChanges
            let listener = Task { for await batch in stream { await changes.add(batch) } }
            defer { listener.cancel() }
            let before = try await v.env.notes.notes(course: nil)
            try mount(v, false)
            defer { try? FileManager.default.removeItem(at: awayURL(v)) }
            try await Task.sleep(nanoseconds: 800_000_000)   // a dozen scans
            let reported = await changes.items
            #expect(reported.isEmpty, "the watcher reported \(reported.count) batches for a missing folder")
            #expect(try await v.env.notes.notes(course: nil) == before, "the index was emptied")
        }
    }

    @Test func servicesRecoverWhenTheFolderComesBack() async throws {
        try await withRobustVault { v in
            try mount(v, false)
            try await Task.sleep(nanoseconds: 400_000_000)
            // While it is away another machine (or the user) changes a note in it.
            let path = try #require(FileManager.default.subpaths(atPath: awayURL(v).path)?.first { $0.hasSuffix("Lecture 8 — Cell membrane.md") || $0.contains("Lecture 8") })
            let away = awayURL(v).appendingPathComponent(path)
            let old = try String(contentsOf: away, encoding: .utf8)
            let fm = Frontmatter.parse(old).frontmatter
            try Data(((fm?.render() ?? "") + "# Lecture 8 — changed while away\n\nnew text\n").utf8).write(to: away)
            try mount(v, true)

            let synced = await eventually { (try? await v.env.notes.open(id: "bio/lecture-8"))?.text.contains("changed while away") == true }
            #expect(synced, "a change made while the vault was away was never picked up")
            // Writes work again, everywhere.
            for op in WriteOp.sequence {
                let code = await robustCode { try await op.run(v.env) }
                #expect(code == nil, "\(op.name) after the vault is back: \(code ?? "")")
            }
            #expect(v.dir.temporaryFiles.isEmpty)
            let ok = await eventually { (try? await readModel(v.env)) == (try? await readModel(try await v.reopened())) }
            #expect(ok, "services disagree with the disk after reconnecting")
        }
    }

    @Test func aDriveThatKeepsFailingWithEIOIsSurvived() async throws {
        try await withRobustVault { v in
            let before = v.files()
            v.fs.inject(.io, ops: ["attributes", "realPath", "readData", "createDirectories", "createFile", "sync", "syncDirectory",
                                   "replaceItem", "moveItemNoReplace", "removeFile", "contentsOfDirectory"])
            await exerciseReads(v.env)
            for op in WriteOp.all {
                let code = await robustCode { try await op.run(v.env) }
                #expect(code != nil && code != "other", "\(op.name): \(code ?? "succeeded on a dead drive")")
            }
            v.fs.clear()
            #expect(v.files() == before)
            for op in WriteOp.sequence {
                let code = await robustCode { try await op.run(v.env) }
                #expect(code == nil, "\(op.name) after the drive is back: \(code ?? "")")
            }
            #expect(await v.matchesRestart(), "services disagree with the files on disk")
        }
    }

    @Test func openingAVaultThatIsNotThereOrNotAFolder() async throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("margin-missing-\(UUID().uuidString)")
        do {
            _ = try await AppEnvironment.vault(at: missing)
            Issue.record("must not open")
        } catch let e as MarginError { #expect(e.code == "notFound", "\(e)") }
        #expect(!FileManager.default.fileExists(atPath: missing.path), "opening must not create the folder")

        let dir = TempDir()
        try dir.seed("plain.txt", Data("a file, not a vault".utf8))
        do {
            _ = try await AppEnvironment.vault(at: dir.file("plain.txt"))
            Issue.record("must not open")
        } catch let e as MarginError { #expect(e.code == "invalid", "\(e)") }
    }

    @Test func aSymlinkedVaultRootSurvivesTheTargetDisappearing() async throws {
        let target = TempDir()
        let store = try await VaultStore.open(root: target.url, clock: FixedClock(), createIfMissing: true)
        try await SampleVaultGenerator.generate(into: store, from: Fixtures.week5)
        let link = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("margin-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.url)
        defer { try? FileManager.default.removeItem(at: link) }
        let env = try await AppEnvironment.vault(at: link, clock: FixedClock(), watchInterval: 0.05)
        let away = target.url.appendingPathExtension("away")
        try FileManager.default.moveItem(at: target.url, to: away)
        defer { try? FileManager.default.removeItem(at: away) }
        let code = await robustCode { try await env.notes.create(course: "bio", title: "Ghost", kind: .note, text: "x", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
        #expect(code == "notFound" || code == "io", "\(code ?? "succeeded")")
        #expect(!FileManager.default.fileExists(atPath: target.url.path))
        await env.shutdown()
    }
}
}
