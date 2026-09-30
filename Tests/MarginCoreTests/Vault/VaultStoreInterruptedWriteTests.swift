import Foundation
import Testing
@testable import MarginCore

/// Acceptance for M5-06: no data loss when a write, create, rename or trash is violently
/// interrupted at ANY step. Every call the store makes is failed in turn, both as a survivable
/// error and as a simulated crash (no cleanup possible), before and after the call executes, and
/// with a half-written temp file for the write step.
@Suite(.tags(.slow)) struct VaultStoreInterruptedWriteTests {
    static let oldBytes = trickyBytes(seed: "orig", kilobytes: 64)
    static let newContent = String(decoding: trickyBytes(seed: "new", kilobytes: 96), as: UTF8.self)
    static var newBytes: Data { Data(newContent.utf8) }
    static let otherBytes = Data("untouched neighbour\n".utf8)

    struct Scenario: Sendable {
        var name: String
        var seed: @Sendable (TempDir) throws -> Void
        var run: @Sendable (VaultStore) async throws -> Void
        /// Problems with the final state (empty = fine). `succeeded`: the operation returned normally.
        var check: @Sendable (TempDir, Bool) -> [String]
    }

    static func overwrite(expectedVersion: Bool) -> Scenario {
        Scenario(
            name: expectedVersion ? "overwrite with expectedVersion" : "overwrite",
            seed: { d in
                try d.seed("Fall/n.md", oldBytes, permissions: 0o640)
                try d.seed("other.md", otherBytes)
            },
            run: { store in
                try await store.write(vp("Fall/n.md"), content: newContent,
                                      expectedVersion: expectedVersion ? ContentHash(of: oldBytes) : nil)
            },
            check: { d, succeeded in
                var problems: [String] = []
                let cur = d.bytes("Fall/n.md")
                if cur != oldBytes && cur != newBytes { problems.append("n.md is neither the old nor the new content (\(cur?.count ?? -1) bytes)") }
                if succeeded && cur != newBytes { problems.append("write reported success but new content is not in place") }
                if d.bytes("other.md") != otherBytes { problems.append("neighbour file changed") }
                let perms = (try? FileManager.default.attributesOfItem(atPath: d.file("Fall/n.md").path)[.posixPermissions]) as? Int
                if perms != 0o640 { problems.append("permissions changed to \(String(describing: perms))") }
                let expectedFiles: Set<String> = ["Fall/n.md", "other.md"]
                let files = Set(d.snapshot().keys.filter { !VaultStore.isTemporaryName(String($0.split(separator: "/").last ?? "")) })
                if files != expectedFiles { problems.append("unexpected files: \(files.sorted())") }
                return problems
            })
    }

    static let newFile = Scenario(
        name: "write new file in new folder",
        seed: { d in try d.seed("other.md", otherBytes) },
        run: { store in try await store.write(vp("A/B/new.md"), content: newContent) },
        check: { d, succeeded in
            var problems: [String] = []
            let cur = d.bytes("A/B/new.md")
            if let cur, cur != newBytes { problems.append("new.md is partial (\(cur.count) bytes)") }
            if succeeded && cur != newBytes { problems.append("success but file missing") }
            if d.bytes("other.md") != otherBytes { problems.append("neighbour file changed") }
            return problems
        })

    static let create = Scenario(
        name: "create",
        seed: { d in try d.seed("other.md", otherBytes) },
        run: { store in try await store.create(vp("created.md"), content: newContent) },
        check: { d, succeeded in
            var problems: [String] = []
            let cur = d.bytes("created.md")
            if let cur, cur != newBytes { problems.append("created.md is partial (\(cur.count) bytes)") }
            if succeeded && cur != newBytes { problems.append("success but file missing") }
            return problems
        })

    static let rename = Scenario(
        name: "rename",
        seed: { d in try d.seed("a/old.md", oldBytes); try d.seed("other.md", otherBytes) },
        run: { store in try await store.rename(vp("a/old.md"), to: vp("b/new.md")) },
        check: { d, succeeded in
            var problems: [String] = []
            let src = d.bytes("a/old.md"), dst = d.bytes("b/new.md")
            if src == nil && dst == nil { problems.append("note vanished") }
            if let src, src != oldBytes { problems.append("source damaged") }
            if let dst, dst != oldBytes { problems.append("target damaged") }
            if succeeded && dst == nil { problems.append("success but target missing") }
            return problems
        })

    static let trash = Scenario(
        name: "trash",
        seed: { d in try d.seed("a/old.md", oldBytes); try d.seed("other.md", otherBytes) },
        run: { store in try await store.trash(vp("a/old.md")) },
        check: { d, succeeded in
            var problems: [String] = []
            let src = d.bytes("a/old.md")
            let trashed = d.snapshot().filter { $0.key.hasPrefix(".margin/trash/") }
            if src == nil && trashed.isEmpty { problems.append("note vanished") }
            if let src, src != oldBytes { problems.append("source damaged") }
            for (k, v) in trashed where v != oldBytes { problems.append("trashed copy \(k) damaged") }
            if succeeded && (src != nil || trashed.isEmpty) { problems.append("success but not in trash") }
            return problems
        })

    static let all = [overwrite(expectedVersion: false), overwrite(expectedVersion: true), newFile, create, rename, trash]

    func makeStore(_ d: TempDir, _ fs: any FileSystem) async throws -> VaultStore {
        try await VaultStore.open(root: d.url, fileSystem: fs, clock: FixedClock(), trash: PortableTrash())
    }

    /// Runs the whole sweep for one scenario and returns the number of fault points exercised.
    @discardableResult
    func sweep(_ s: Scenario) async throws -> Int {
        // Baseline: no fault, learn which calls the operation makes.
        let baseDir = TempDir()
        try s.seed(baseDir)
        let baseFS = FaultInjectingFileSystem()
        let baseStore = try await makeStore(baseDir, baseFS)
        baseFS.resetCounter()
        try await s.run(baseStore)
        let calls = baseFS.log
        #expect(calls.count >= 4, "\(s.name): suspiciously few file-system calls: \(calls)")
        #expect(s.check(baseDir, true).isEmpty, "\(s.name): baseline broken: \(s.check(baseDir, true))")

        var cases = 0
        for index in 0..<calls.count {
            for afterExecuting in [false, true] {
                for mode in [FaultInjectingFileSystem.Mode.error, .crash] {
                    let partials = (calls[index] == "createFile" && !afterExecuting) ? [false, true] : [false]
                    for partialWrite in partials {
                        cases += 1
                        let label = "\(s.name): call #\(index) \(calls[index]) after=\(afterExecuting) \(mode) partial=\(partialWrite)"
                        let d = TempDir()
                        try s.seed(d)
                        let fs = FaultInjectingFileSystem()
                        let store = try await makeStore(d, fs)
                        fs.arm(.init(index: index, afterExecuting: afterExecuting, mode: mode, partialWrite: partialWrite))
                        var succeeded = false
                        do { try await s.run(store); succeeded = true } catch {}

                        // A survivable error must not leave garbage behind.
                        if mode == .error { #expect(d.temporaryFiles.isEmpty, "\(label): temp garbage after error: \(d.temporaryFiles)") }
                        #expect(s.check(d, succeeded).isEmpty, "\(label): \(s.check(d, succeeded))")

                        // Whatever is on disk, `list` must show only real notes.
                        fs.revive()
                        let listed = try await store.list().map(\.rawValue)
                        let expectedListed = d.snapshot().keys.filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } && $0.hasSuffix(".md") }.sorted()
                        #expect(listed == expectedListed, "\(label): list \(listed) vs disk \(expectedListed)")

                        // Next launch: leftovers are cleaned, nothing else changes.
                        let before = d.snapshot().filter { !VaultStore.isTemporaryName(String($0.key.split(separator: "/").last ?? "")) }
                        let reopened = try await VaultStore.open(root: d.url, clock: FixedClock(), trash: PortableTrash())
                        #expect(d.temporaryFiles.isEmpty, "\(label): temp garbage after reopen")
                        #expect(await reopened.recoveredTemporaryFiles.count <= 1, "\(label)")
                        #expect(d.snapshot() == before, "\(label): reopen changed real files")
                        #expect(s.check(d, succeeded).isEmpty, "\(label): after reopen \(s.check(d, succeeded))")
                    }
                }
            }
        }
        return cases
    }

    @Test func overwriteSurvivesEveryInterruption() async throws { try await sweep(Self.overwrite(expectedVersion: false)) }
    @Test func guardedOverwriteSurvivesEveryInterruption() async throws { try await sweep(Self.overwrite(expectedVersion: true)) }
    @Test func newFileSurvivesEveryInterruption() async throws { try await sweep(Self.newFile) }
    @Test func createSurvivesEveryInterruption() async throws { try await sweep(Self.create) }
    @Test func renameSurvivesEveryInterruption() async throws { try await sweep(Self.rename) }
    @Test func trashSurvivesEveryInterruption() async throws { try await sweep(Self.trash) }

    @Test func sweepExercisesManyFaultPoints() async throws {
        var total = 0
        for s in Self.all { total += try await sweep(s) }
        print("interrupted-write sweep: \(total) fault cases across \(Self.all.count) operations")
        #expect(total >= 100)
    }

    // MARK: Named fault points from the task description

    /// Index of the first call named `name` in a baseline overwrite.
    func overwriteCallIndex(_ name: String) async throws -> Int {
        let d = TempDir()
        try Self.overwrite(expectedVersion: false).seed(d)
        let fs = FaultInjectingFileSystem()
        let store = try await makeStore(d, fs)
        fs.resetCounter()
        try await Self.overwrite(expectedVersion: false).run(store)
        return try #require(fs.log.firstIndex(of: name), "no \(name) call in \(fs.log)")
    }

    struct NamedFault: CustomStringConvertible {
        var call: String; var after: Bool; var partial: Bool
        var description: String { "\(call) after=\(after) partial=\(partial)" }
    }

    @Test(arguments: [
        NamedFault(call: "createFile", after: false, partial: true),   // partial write
        NamedFault(call: "createFile", after: true, partial: false),   // after temp write
        NamedFault(call: "sync", after: false, partial: false),        // before fsync
        NamedFault(call: "replaceItem", after: false, partial: false), // before rename
    ])
    func namedFaultLeavesOriginalIntact(_ f: NamedFault) async throws {
        let index = try await overwriteCallIndex(f.call)
        for mode in [FaultInjectingFileSystem.Mode.error, .crash] {
            let d = TempDir()
            try Self.overwrite(expectedVersion: false).seed(d)
            let fs = FaultInjectingFileSystem()
            let store = try await makeStore(d, fs)
            fs.arm(.init(index: index, afterExecuting: f.after, mode: mode, partialWrite: f.partial))
            await #expect(throws: MarginError.self) { try await store.write(vp("Fall/n.md"), content: Self.newContent) }
            #expect(d.bytes("Fall/n.md") == Self.oldBytes, "\(f) \(mode): original changed")
            if mode == .crash {
                // The killed process left its temp file; it is invisible to list…
                #expect(d.temporaryFiles.count == 1, "\(f): expected one leftover temp, got \(d.temporaryFiles)")
                fs.revive()
                #expect(try await store.list().map(\.rawValue) == ["Fall/n.md", "other.md"])
                // …and the next open removes it.
                let reopened = try await VaultStore.open(root: d.url, trash: PortableTrash())
                #expect(await reopened.recoveredTemporaryFiles.count == 1)
                #expect(d.temporaryFiles.isEmpty)
            } else {
                #expect(d.temporaryFiles.isEmpty)
            }
            #expect(d.bytes("Fall/n.md") == Self.oldBytes)
            // The store still works afterwards and can complete the write.
            let fresh = try await VaultStore.open(root: d.url, trash: PortableTrash())
            try await fresh.write(vp("Fall/n.md"), content: Self.newContent, expectedVersion: ContentHash(of: Self.oldBytes))
            #expect(d.bytes("Fall/n.md") == Self.newBytes)
        }
    }

    @Test func failedDirectorySyncAfterRenameReportsErrorButKeepsNewContent() async throws {
        let index = try await overwriteCallIndex("syncDirectory")
        let d = TempDir()
        try Self.overwrite(expectedVersion: false).seed(d)
        let fs = FaultInjectingFileSystem()
        let store = try await makeStore(d, fs)
        fs.arm(.init(index: index, afterExecuting: false, mode: .error))
        do {
            try await store.write(vp("Fall/n.md"), content: Self.newContent)
            Issue.record("must report the failed sync")
        } catch let e as MarginError { #expect(e.code == "io") }
        #expect(d.bytes("Fall/n.md") == Self.newBytes)
    }

    @Test func realFileSystemErrorLeavesOriginalIntact() async throws {
        // Not injected: a genuinely failing rename (target is a non-empty folder on Linux would
        // be caught earlier), so use a read-only folder to make temp creation fail for real.
        let d = TempDir()
        try d.seed("ro/n.md", Self.oldBytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.file("ro").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.file("ro").path) }
        if geteuid() == 0 { return } // root ignores directory permissions
        let store = try await VaultStore.open(root: d.url, trash: PortableTrash())
        await #expect(throws: MarginError.self) { try await store.write(vp("ro/n.md"), content: Self.newContent) }
        #expect(d.bytes("ro/n.md") == Self.oldBytes)
        #expect(d.temporaryFiles.isEmpty)
    }
}
