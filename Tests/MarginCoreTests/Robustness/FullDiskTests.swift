import Foundation
import Testing
@testable import MarginCore

extension Robustness {
/// M12-03, full disk. Every service that writes is run while `ENOSPC` hits each step of the atomic
/// write (temp file create, half-written temp file, fsync, rename, folder creation, folder fsync).
/// The disk cannot be filled safely inside the test container, so the error is simulated at the
/// `FileSystem` seam with the exact errno text of the real failure (`ScriptedFileSystem`).
///
/// Required of every case: no crash, a typed `MarginError` (`.io`), no original file lost or
/// changed (single-step operations), no temporary file left, and the services answer again, with
/// the same picture as a restarted app, once space is back.
@Suite struct FullDiskTests {
    struct Fault: Sendable, CustomTestStringConvertible {
        var name: String
        var rule: ScriptedFileSystem.Rule
        /// The fault hits before the store changed anything; the vault must be byte-identical afterwards.
        var untouched: Bool
        var testDescription: String { name }

        static let all: [Fault] = [
            Fault(name: "ENOSPC creating the temp file", rule: .init(ops: ["createFile"], pathContains: nil, failure: .noSpace), untouched: true),
            Fault(name: "ENOSPC half way through the temp file", rule: .init(ops: ["createFile"], pathContains: nil, failure: .noSpace, partialWrite: true), untouched: true),
            Fault(name: "ENOSPC in fsync", rule: .init(ops: ["sync"], pathContains: nil, failure: .noSpace), untouched: true),
            Fault(name: "ENOSPC in rename", rule: .init(ops: ["replaceItem", "moveItemNoReplace"], pathContains: nil, failure: .noSpace), untouched: true),
            Fault(name: "ENOSPC creating a folder", rule: .init(ops: ["createDirectories"], pathContains: nil, failure: .noSpace), untouched: true),
            Fault(name: "ENOSPC in the folder fsync after the rename", rule: .init(ops: ["syncDirectory"], pathContains: nil, failure: .noSpace), untouched: false),
            Fault(name: "ENOSPC reported after the rename happened", rule: .init(ops: ["replaceItem", "moveItemNoReplace"], pathContains: nil, failure: .noSpace, afterExecuting: true), untouched: false),
        ]
    }

    /// Operations that change several files in a row: a failure between the steps may leave the
    /// first step done (never a loss: "a copy, not a loss").
    static let multiStep: Set<String> = ["inbox.triage", "courseWriter.rename", "notes.move", "courseWriter.setArchived"]

    /// Files of `before` that are neither intact at their path nor present with the same bytes somewhere else.
    static func lost(_ before: [String: Data], in after: [String: Data], allowModified: Bool) -> [String] {
        let bytes = Set(after.values)
        return before.filter { path, data in
            if after[path] == data { return false }
            if after[path] != nil { return !allowModified }   // same path, other content
            return !bytes.contains(data)                       // moved or trashed keeps its bytes
        }.keys.sorted()
    }

    @Test(arguments: WriteOp.all, Fault.all)
    func writeFailsCleanlyAndServicesRecover(op: WriteOp, fault: Fault) async throws {
        try await withRobustVault { v in
            let before = v.files()
            v.fs.inject(fault.rule)
            let code = await robustCode { try await op.run(v.env) }
            // Some operations never reach the failing step (a delete does not create a file).
            if v.fs.injectedCount == 0 { #expect(code == nil, "\(op.name): failed without a fault: \(code ?? "")") }
            else if let code { #expect(code == "io", "\(op.name) / \(fault.name): expected io, got \(code)") }
            let failed = code != nil

            #expect(v.dir.temporaryFiles.isEmpty, "\(op.name) / \(fault.name): temp files left: \(v.dir.temporaryFiles)")
            let after = v.files()
            let lost = Self.lost(before, in: after, allowModified: !fault.untouched || Self.multiStep.contains(op.name) || !failed)
            #expect(lost.isEmpty, "\(op.name) / \(fault.name): data lost or changed: \(lost)")
            if failed && fault.untouched && !Self.multiStep.contains(op.name) {
                #expect(after == before, "\(op.name) / \(fault.name): vault changed by a failed write")
            }

            // Reading still works while the disk is full.
            await exerciseReads(v.env)

            // Space is back: the service is consistent with the disk and the write can be repeated.
            v.fs.clear()
            let fresh = try await v.reopened()
            let ok = await eventually { (try? await readModel(v.env)) == (try? await readModel(fresh)) }
            #expect(ok, "\(op.name) / \(fault.name): services disagree with the files on disk after the failure")
            await fresh.shutdown()

            if failed {
                let retry = await robustCode { try await op.run(v.env) }
                // When the change did happen although the error said otherwise, the repeat finds it done.
                let accepted: [String?] = fault.untouched ? [nil] : [nil, "conflict", "notFound"]
                #expect(accepted.contains(retry), "\(op.name) / \(fault.name): retry after the fault cleared failed with \(retry ?? "")")
            }
            let fresh2 = try await v.reopened()
            let ok2 = await eventually { (try? await readModel(v.env)) == (try? await readModel(fresh2)) }
            #expect(ok2, "\(op.name) / \(fault.name): services disagree with the files after the retry")
            await fresh2.shutdown()
            #expect(v.dir.temporaryFiles.isEmpty)
        }
    }

    @Test func aDiskThatIsFullFromTheStartStillReads() async throws {
        try await withRobustVault { v in
            v.fs.inject(.noSpace, ops: ["createFile", "createDirectories", "sync", "syncDirectory", "replaceItem", "moveItemNoReplace"])
            let before = v.files()
            let model = try await readModel(v.env)
            await exerciseReads(v.env)
            for op in WriteOp.all {
                let code = await robustCode { try await op.run(v.env) }
                #expect(code == "io", "\(op.name): \(code ?? "succeeded")")
            }
            #expect(v.files() == before)
            #expect(v.dir.temporaryFiles.isEmpty)
            #expect(try await readModel(v.env) == model)
            v.fs.clear()
            // (Every operation after a fault is covered one by one above; a few in a row here.)
            for name in ["notes.save", "notes.create", "tasks.toggle", "capture inbox", "properties.set"] {
                let op = try #require(WriteOp.all.first { $0.name == name })
                let code = await robustCode { try await op.run(v.env) }
                #expect(code == nil, "\(name) after space is back: \(code ?? "")")
            }
        }
    }

    @Test func fullDiskDuringADryRunNeverMatters() async throws {
        try await withRobustVault { v in
            v.fs.inject(.noSpace, ops: ["createFile", "createDirectories", "sync", "syncDirectory", "replaceItem", "moveItemNoReplace"])
            let cs = try await v.env.notes.save(id: "bio/lecture-8", text: "changed", actor: robustActor, baseVersion: nil, dryRun: true, idempotencyKey: nil)
            #expect(cs.isDryRun && cs.entries.count == 1)
            #expect(v.fs.injectedCount == 0)
        }
    }

    @Test func aFailedWriteIsNotRememberedByTheIdempotencyCache() async throws {
        try await withRobustVault { v in
            v.fs.inject(.noSpace, ops: ["createFile"])
            let args = { @Sendable () async throws -> ChangeSet in
                try await v.env.notes.save(id: "bio/lecture-8", text: "retry me", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: "key-1")
            }
            #expect(await robustCode { try await args() } == "io")
            v.fs.clear()
            let cs = try await args()
            #expect(cs.entries.count == 1)
            #expect(try await v.env.notes.open(id: "bio/lecture-8").text == "retry me")
        }
    }
}
}
