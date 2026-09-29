import Foundation
import Testing
@testable import MarginCore

/// AG-03 acceptance: "crash mid-apply". Every file-system call of a multi-file group (and of its
/// undo) is failed in turn, before and after it executes, both as a survivable error and as a
/// simulated kill (nothing can clean up afterwards). After a restart the group is either completely
/// there or completely absent, and the journal agrees with the files.
@Suite struct ChangeSetCrashTests {
    typealias Files = [String: Data]

    enum Phase: String, Sendable { case group, undo }

    struct Outcome: Sendable {
        var failure: String?
        var crashed: Bool
    }

    /// One run of a scenario with a fault at `fault` (nil: no fault, used to count calls).
    private func run(phase: Phase, fault: FaultInjectingFileSystem.Fault?, dir: TempDir) async throws
        -> (calls: [String], threw: Bool, committedListed: Bool?, id: String?) {
        try ChangeSetJournalTests.seed(dir)
        let fs = FaultInjectingFileSystem()
        let (store, journal) = try await openJournal(dir, fileSystem: fs)
        var undoTarget: String?
        if phase == .undo {
            undoTarget = try await ChangeSetJournalTests.multiFileWrite(store, journal).id
        }
        fs.arm(fault)
        var threw = false
        do {
            switch phase {
            case .group: _ = try await ChangeSetJournalTests.multiFileWrite(store, journal)
            case .undo: _ = try await journal.undo(id: try #require(undoTarget), actor: .user, mode: .strict, dryRun: false)
            }
        } catch { threw = true }
        return (fs.log, threw, nil, undoTarget)
    }

    /// Restart: a new process opens the same folder on the real file system.
    private func reopen(_ dir: TempDir) async throws -> (journal: ChangeSetJournal, changes: [ChangeSet]) {
        let (_, journal) = try await openJournal(dir)
        return (journal, await journal.changes(limit: nil))
    }

    private func describe(_ f: FaultInjectingFileSystem.Fault, _ name: String) -> String {
        "call \(f.index) (\(name)) \(f.afterExecuting ? "after" : "before") executing, \(f.mode == .crash ? "crash" : "error")\(f.partialWrite ? ", partial write" : "")"
    }

    /// Runs the sweep and returns the problems found.
    private func sweep(phase: Phase, every step: Int = 1) async throws -> (problems: [String], runs: Int, calls: Int) {
        // 1. Count the calls of a clean run.
        let probeDir = TempDir()
        let probe = try await run(phase: phase, fault: nil, dir: probeDir)
        #expect(!probe.threw)
        let calls = probe.calls
        var problems: [String] = []
        var runs = 0

        var faults: [FaultInjectingFileSystem.Fault] = []
        for index in stride(from: 0, to: calls.count, by: step) {
            for mode in [FaultInjectingFileSystem.Mode.crash, .error] {
                for after in [false, true] {
                    faults.append(.init(index: index, afterExecuting: after, mode: mode))
                }
            }
            if calls[index] == "createFile" {
                faults.append(.init(index: index, afterExecuting: false, mode: .crash, partialWrite: true))
            }
        }

        for fault in faults {
            runs += 1
            let dir = TempDir()
            let name = calls[fault.index]
            let result = try await run(phase: phase, fault: fault, dir: dir)
            let label = "[\(phase.rawValue)] " + describe(fault, name)

            // With a survivable error the live process has already cleaned up: check before any restart.
            if fault.mode == .error {
                let live = classify(dir.userFiles(), phase: phase)
                if live == .mixed { problems.append("\(label): files are mixed WITHOUT a restart") }
            }

            let (journal, changes) = try await reopen(dir)
            let files = dir.userFiles()
            let state = classify(files, phase: phase)
            let listed = changes.count
            let expectedListedWhenDone = phase == .group ? 1 : 2       // undo phase: the original plus the undo
            let leftovers = dir.journalFiles().filter { $0.contains(".op-") }.count
            let metas = dir.journalFiles().filter { $0.hasSuffix(".meta.json") }.count

            switch state {
            case .mixed:
                problems.append("\(label): files are neither all before nor all after")
            case .before:
                // Group: nothing recorded. Undo phase: the undo did not happen; only the original is recorded.
                let want = phase == .group ? 0 : 1
                if listed != want { problems.append("\(label): \(listed) change sets listed, expected \(want) for the untouched state") }
            case .after:
                if listed != expectedListedWhenDone { problems.append("\(label): \(listed) change sets listed, expected \(expectedListedWhenDone) for the finished state") }
            }
            if leftovers != listed * 5 {
                // Op files exist only for committed records (5 operations each).
                problems.append("\(label): \(leftovers) op files, \(metas) records, \(listed) listed")
            }
            if metas != listed { problems.append("\(label): \(metas) record files but \(listed) listed") }
            let report = await journal.recovery
            if !report.problems.isEmpty { problems.append("\(label): recovery reported \(report.problems)") }
            if !report.unreadable.isEmpty { problems.append("\(label): unreadable records \(report.unreadable)") }
            if dir.bytes("keep.md") != ChangeSetJournalTests.neighbour { problems.append("\(label): neighbour changed") }
            if !dir.temporaryFiles.isEmpty { problems.append("\(label): temp files left \(dir.temporaryFiles)") }
            if result.threw == false && state != .after {
                problems.append("\(label): reported success but the group is not applied")
            }
            // The state is stable: a second restart changes nothing.
            let (_, second) = try await reopen(dir)
            if second.map(\.id) != changes.map(\.id) || dir.userFiles() != files { problems.append("\(label): second restart changed state") }
        }
        return (problems, runs, calls.count)
    }

    private enum State { case before, after, mixed }

    private func classify(_ files: Files, phase: Phase) -> State {
        switch phase {
        case .group:
            if files == ChangeSetJournalTests.multiFileOld { return .before }
            if files == ChangeSetJournalTests.multiFileNew { return .after }
            return .mixed
        case .undo:
            // Before the undo the group is applied; after it the original files are back.
            if files == ChangeSetJournalTests.multiFileNew { return .before }
            if files == ChangeSetJournalTests.multiFileOld { return .after }
            return .mixed
        }
    }

    @Test func aGroupOfFiveOperationsIsAllOrNothingAtEveryFailurePoint() async throws {
        let result = try await sweep(phase: .group)
        print("group sweep: \(result.calls) file-system calls, \(result.runs) faulted runs")
        #expect(result.runs > 300)
        #expect(result.problems.isEmpty, "\(result.problems.prefix(12).joined(separator: "\n"))")
    }

    @Test func anUndoIsAllOrNothingAtEveryFailurePoint() async throws {
        let result = try await sweep(phase: .undo)
        print("undo sweep: \(result.calls) file-system calls, \(result.runs) faulted runs")
        #expect(result.runs > 300)
        #expect(result.problems.isEmpty, "\(result.problems.prefix(12).joined(separator: "\n"))")
    }

    /// Expiring old records must never look like an interrupted group: a crash while deleting them
    /// must not roll anything back on the next start.
    @Test func aCrashWhileExpiringOldRecordsRollsNothingBack() async throws {
        func runCommit(fault: FaultInjectingFileSystem.Fault?, dir: TempDir) async throws -> [String] {
            try dir.seed("n.md", Data("v0\n".utf8))
            let fs = FaultInjectingFileSystem()
            let (store, journal) = try await openJournal(dir, fileSystem: fs, retention: .init(maxAge: 1_000_000, maxCount: 2))
            for i in 1...2 {
                let expected = ContentHash(of: "v\(i - 1)\n")
                _ = try await journal.transaction(actor: .user, idempotencyKey: nil, body: {
                    try await store.write(vp("n.md"), content: "v\(i)\n", expectedVersion: expected); return []
                })
            }
            fs.arm(fault)
            _ = try? await journal.transaction(actor: .user, idempotencyKey: nil, body: {
                try await store.write(vp("n.md"), content: "v3\n", expectedVersion: ContentHash(of: "v2\n")); return []
            })
            return fs.log
        }
        let probe = try await runCommit(fault: nil, dir: TempDir())
        var problems: [String] = []
        for index in 0..<probe.count {
            for mode in [FaultInjectingFileSystem.Mode.crash, .error] {
                for after in [false, true] {
                    let dir = TempDir()
                    _ = try await runCommit(fault: .init(index: index, afterExecuting: after, mode: mode), dir: dir)
                    let (_, journal) = try await openJournal(dir, retention: .init(maxAge: 1_000_000, maxCount: 2))
                    let text = String(decoding: dir.bytes("n.md") ?? Data(), as: UTF8.self)
                    let label = "call \(index) (\(probe[index])) \(after ? "after" : "before") \(mode)"
                    if text != "v2\n" && text != "v3\n" { problems.append("\(label): file is \(text.debugDescription)") }
                    let listed = await journal.changes(limit: nil).count
                    if listed > 2 { problems.append("\(label): \(listed) records") }
                    // Only the unfinished third group may be rolled back (file v2); once it committed (file
                    // v3) nothing is rolled back, however far the expiry of the oldest record got.
                    let rolledBack = await journal.recovery.rolledBack.count
                    if rolledBack > 1 { problems.append("\(label): \(rolledBack) groups rolled back") }
                    if text == "v3\n" && rolledBack != 0 { problems.append("\(label): committed group rolled back") }
                    if rolledBack == 1 && text != "v2\n" { problems.append("\(label): rolled back but file is \(text.debugDescription)") }
                }
            }
        }
        #expect(problems.isEmpty, "\(problems.prefix(10).joined(separator: "\n"))")
    }
}
