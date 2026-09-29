import Foundation

/// A placeholder id and the stable id that replaced it (migration from path/line derived ids).
public struct IDMigration: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case note, task }

    public var kind: Kind
    public var path: VaultPath
    /// The id `NoteIndex` used before the pass: the path without `.md` for a note, `<noteID>#L<line>`
    /// for a task.
    public var oldID: String
    public var newID: String
}

/// One file the pass wants to change.
public struct PlannedIDEdit: Sendable, Hashable {
    public var path: VaultPath
    /// Version of the bytes the edit was computed from; the write fails with `.conflict` when the
    /// file changed since.
    public var version: ContentHash
    public var result: IDAssignmentResult
}

/// A file the pass did not change, with the reason.
public struct IDAssignmentSkip: Sendable, Hashable {
    public var path: VaultPath
    public var error: MarginError
}

/// What `IDAssignmentPass.plan` decided; nothing has been written yet.
public struct IDAssignmentPlan: Sendable, Hashable {
    public var scanned: Int
    public var edits: [PlannedIDEdit]
    public var skipped: [IDAssignmentSkip]
}

/// Outcome of a pass.
public struct IDAssignmentReport: Sendable, Hashable {
    public var scanned: Int
    /// Files written (or that would be written with `dryRun`), in path order.
    public var changed: [VaultPath]
    public var notesAssigned: Int
    public var tasksAssigned: Int
    /// Notes and tasks whose duplicate id was replaced.
    public var duplicatesReassigned: Int
    public var migrations: [IDMigration]
    /// Unreadable files, notes with unsafe frontmatter (informational) and writes that lost a
    /// race with another writer (`.conflict`); those are picked up by the next run.
    public var skipped: [IDAssignmentSkip]
    public var dryRun: Bool

    /// `true` when nothing had to change.
    public var isNoop: Bool { changed.isEmpty }
}

/// Assigns stable ids across the vault (D-012, AG-02) and migrates from placeholder ids.
///
/// Every markdown note (except `_course.md`) is read through the `VaultStore`, processed in path
/// order by `IDAssigner` and, when something is missing, written back atomically with the version
/// that was read as `expectedVersion`. The store registers each write with its `OwnWriteRegistry`,
/// so a file watcher does not report the pass's own changes back. The pass is idempotent: a second
/// run finds every id in place and writes nothing.
///
/// Duplicates (a copy-pasted task line or note): the first owner in path and line order keeps
/// the id, later ones get a new id.
public actor IDAssignmentPass {
    private nonisolated let dedicatedExecutor = DedicatedExecutor(label: "margin.id-assignment")
    public nonisolated var unownedExecutor: UnownedSerialExecutor { dedicatedExecutor.asUnownedSerialExecutor() }
    private let store: VaultStore
    private var generator: StableIDGenerator
    private let assigner = IDAssigner()

    public init(store: VaultStore, generator: StableIDGenerator = StableIDGenerator()) {
        self.store = store
        self.generator = generator
    }

    /// Reads the vault and computes the edits. Ids are always checked against the whole vault;
    /// `scope` only limits which files are edited.
    public func plan(scope: Set<VaultPath>? = nil) async throws -> IDAssignmentPlan {
        let paths = try await store.list().filter { $0.lastComponent != "_course.md" }
        var loaded: [(path: VaultPath, text: String, version: ContentHash)] = []
        var skipped: [IDAssignmentSkip] = []
        for path in paths {
            do {
                let (text, version) = try await store.read(path)
                loaded.append((path, text, version))
            } catch {
                skipped.append(IDAssignmentSkip(path: path, error: (error as? MarginError) ?? .io("\(error)")))
            }
        }

        var reserved = Set<String>()
        for file in loaded {
            let ids = assigner.existingIDs(in: file.text)
            if let n = ids.note { reserved.insert(n) }
            reserved.formUnion(ids.tasks)
        }

        var ledger = IDLedger(reserved: reserved)
        var edits: [PlannedIDEdit] = []
        for file in loaded {
            let result = assigner.assign(to: file.text, ledger: &ledger, generator: &generator)
            if case .skipped(let reason) = result.noteOutcome {
                skipped.append(IDAssignmentSkip(path: file.path, error: .invalid("\(file.path): \(reason); note id not assigned")))
            }
            guard result.didChange, scope?.contains(file.path) ?? true else { continue }
            edits.append(PlannedIDEdit(path: file.path, version: file.version, result: result))
        }
        return IDAssignmentPlan(scanned: loaded.count, edits: edits, skipped: skipped)
    }

    /// Writes a plan. A file that changed since it was read is left alone and reported as skipped.
    public func apply(_ plan: IDAssignmentPlan) async -> IDAssignmentReport {
        var written: [PlannedIDEdit] = []
        var skipped = plan.skipped
        for edit in plan.edits {
            do {
                try await store.write(edit.path, content: edit.result.text, expectedVersion: edit.version)
                written.append(edit)
            } catch {
                skipped.append(IDAssignmentSkip(path: edit.path, error: (error as? MarginError) ?? .io("\(error)")))
            }
        }
        return Self.report(scanned: plan.scanned, edits: written, skipped: skipped, dryRun: false)
    }

    /// Plans and (unless `dryRun`) applies in one step.
    public func run(scope: Set<VaultPath>? = nil, dryRun: Bool = false) async throws -> IDAssignmentReport {
        let plan = try await plan(scope: scope)
        if dryRun {
            return Self.report(scanned: plan.scanned, edits: plan.edits, skipped: plan.skipped, dryRun: true)
        }
        return await apply(plan)
    }

    static func report(scanned: Int, edits: [PlannedIDEdit], skipped: [IDAssignmentSkip], dryRun: Bool) -> IDAssignmentReport {
        var notes = 0, tasks = 0, dups = 0
        var migrations: [IDMigration] = []
        for edit in edits {
            let r = edit.result
            let stem = NoteIndex.stripExtension(edit.path.rawValue)
            var oldNoteID = stem
            switch r.noteOutcome {
            case .added:
                notes += 1
                if let id = r.noteID { migrations.append(IDMigration(kind: .note, path: edit.path, oldID: stem, newID: id)) }
            case .replacedDuplicate(let old):
                dups += 1
                oldNoteID = old
            case .kept:
                oldNoteID = r.noteID ?? stem
            case .skipped:
                break
            }
            for t in r.tasks {
                switch t.outcome {
                case .added:
                    tasks += 1
                    migrations.append(IDMigration(kind: .task, path: edit.path, oldID: "\(oldNoteID)#L\(t.line)", newID: t.id))
                case .replacedDuplicate:
                    dups += 1
                case .kept, .duplicateKept:
                    break
                }
            }
        }
        return IDAssignmentReport(scanned: scanned, changed: edits.map(\.path), notesAssigned: notes,
                                  tasksAssigned: tasks, duplicatesReassigned: dups, migrations: migrations,
                                  skipped: skipped, dryRun: dryRun)
    }
}
