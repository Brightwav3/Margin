import Foundation
import Testing
@testable import MarginCore

/// AG-03 / AG-04 through the public services only: one suite, run against the fixture and the vault
/// implementation (contract §5). The vault-only guarantees (bit-for-bit bytes, crash safety,
/// multi-file groups) are in `Tests/MarginCoreTests/ChangeSets/`.
@Suite struct ChangeSetStoreConformanceTests {
    // MARK: Helpers

    private static let lines = (1...12).map { "line \($0)\n" }.joined()

    /// Creates a scratch note with twelve numbered lines and returns its id.
    private func sandbox(_ h: Harness, course: CourseID = "bio", title: String = "Sandbox") async throws -> NoteID {
        let cs = try await h.notes.create(course: course, title: title, kind: .note, text: Self.lines, actor: .user,
                                          baseVersion: nil, dryRun: false, idempotencyKey: nil)
        return try #require(cs.entries.first?.noteID)
    }

    @discardableResult
    private func save(_ h: Harness, _ id: NoteID, _ text: String, base: String?, actor: Actor = testActor,
                      dryRun: Bool = false, key: String? = nil) async throws -> ChangeSet {
        try await h.notes.save(id: id, text: text, actor: actor, baseVersion: base, dryRun: dryRun, idempotencyKey: key)
    }

    private func code(_ body: () async throws -> some Any) async -> String? {
        do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other:\(error)" }
    }

    private func changeIDs(_ h: Harness, limit: Int? = nil) async throws -> [String] {
        try await h.changes.changes(limit: limit).map(\.id)
    }

    private func replacing(_ line: Int, with text: String, in body: String = ChangeSetStoreConformanceTests.lines) -> String {
        body.replacingOccurrences(of: "line \(line)\n", with: "\(text)\n")
    }

    // MARK: Undo of each kind of write

    @Test(arguments: HarnessKind.allCases)
    func undoingASaveRestoresTheTextAndTheVersion(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: "bio/glossary")
            let cs = try await save(h, "bio/glossary", "# Glossary\n\nchanged\n", base: before.version)
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            let after = try await h.notes.open(id: "bio/glossary")
            #expect(after.text == before.text)
            #expect(after.version == before.version)
            #expect(undo.revertsID == cs.id && !undo.isDryRun)
            #expect(undo.entries.count == 1 && undo.entries[0].kind == .modified)
            #expect(undo.entries[0].beforeHash == cs.entries[0].afterHash)
            #expect(undo.entries[0].afterHash == before.version)
            #expect(undo.entries[0].noteID == "bio/glossary")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingACreateRemovesTheNote(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.notes.create(course: "bio", title: "Fresh note", kind: .note, text: "", actor: .user,
                                              baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let id = try #require(cs.entries.first?.noteID)
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(undo.entries.count == 1 && undo.entries[0].kind == .deleted && undo.entries[0].noteID == id)
            #expect(await code { try await h.notes.open(id: id) } == "notFound")
            #expect(try await !h.notes.notes(course: "bio").map(\.id).contains(id))
            // The title is free again.
            let again = try await h.notes.create(course: "bio", title: "Fresh note", kind: .note, text: "", actor: .user,
                                                 baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(again.entries.first?.noteID == id)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingAMoveMovesTheNoteBack(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: "bio/glossary")
            let cs = try await h.notes.move(id: "bio/glossary", toCourse: "chem", actor: testActor,
                                            baseVersion: before.version, dryRun: false, idempotencyKey: nil)
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(undo.entries.first?.kind == .moved)
            #expect(undo.entries.first?.fromPath == cs.entries[0].path && undo.entries.first?.path == cs.entries[0].fromPath)
            let after = try await h.notes.open(id: "bio/glossary")
            #expect(after.summary.courseID == "bio")
            #expect(after.text == before.text && after.version == before.version)
            #expect(try await h.notes.notes(course: "bio").map(\.id).contains("bio/glossary"))
            #expect(try await !h.notes.notes(course: "chem").map(\.id).contains("bio/glossary"))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingADeleteRestoresTheNoteWithItsContent(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: "bio/glossary")
            let cs = try await h.notes.delete(id: "bio/glossary", actor: testActor, baseVersion: before.version,
                                              dryRun: false, idempotencyKey: nil)
            #expect(await code { try await h.notes.open(id: "bio/glossary") } == "notFound")
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(undo.entries.first?.kind == .created && undo.entries.first?.noteID == "bio/glossary")
            let after = try await h.notes.open(id: "bio/glossary")
            #expect(after.text == before.text && after.version == before.version)
            #expect(after.summary.courseID == "bio")
            #expect(try await h.notes.notes(course: "bio").map(\.id).contains("bio/glossary"))
        }
    }

    // MARK: Redo (undo of an undo)

    @Test(arguments: HarnessKind.allCases)
    func redoAfterUndoOfASave(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let cs = try await save(h, "bio/glossary", "# Glossary\n\nchanged\n", base: v0.version)
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            let redo = try await h.changes.undo(id: undo.id, actor: .user)
            #expect(redo.revertsID == undo.id)
            let now = try await h.notes.open(id: "bio/glossary")
            #expect(now.text == "# Glossary\n\nchanged\n" && now.version == cs.entries[0].afterHash)
            // And back again.
            _ = try await h.changes.undo(id: redo.id, actor: .user)
            #expect(try await h.notes.open(id: "bio/glossary").version == v0.version)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func redoAfterUndoOfACreate(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.notes.create(course: "bio", title: "Fresh note", kind: .note, text: "body\n", actor: .user,
                                              baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let id = try #require(cs.entries.first?.noteID)
            let original = try await h.notes.open(id: id)
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            _ = try await h.changes.undo(id: undo.id, actor: .user)
            let back = try await h.notes.open(id: id)
            #expect(back.text == original.text && back.version == original.version)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func redoAfterUndoOfADelete(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let cs = try await h.notes.delete(id: "bio/glossary", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            _ = try await h.changes.undo(id: undo.id, actor: .user)
            #expect(await code { try await h.notes.open(id: "bio/glossary") } == "notFound")
            // A third undo brings it back for good.
            let all = try await h.changes.changes()
            #expect(all.count == 3)
            _ = try await h.changes.undo(id: all[0].id, actor: .user)
            #expect(try await h.notes.open(id: "bio/glossary").version == v0.version)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func redoAfterUndoOfAMove(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.notes.move(id: "bio/glossary", toCourse: "chem", actor: .user, baseVersion: nil,
                                            dryRun: false, idempotencyKey: nil)
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            _ = try await h.changes.undo(id: undo.id, actor: .user)
            #expect(try await h.notes.open(id: "bio/glossary").summary.courseID == "chem")
        }
    }

    // MARK: Order and safety

    @Test(arguments: HarnessKind.allCases)
    func undoingSeveralWritesInReverseOrderRestoresTheOriginal(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let a = try await save(h, "bio/glossary", "# Glossary\n\none\n", base: v0.version)
            let b = try await save(h, "bio/glossary", "# Glossary\n\ntwo\n", base: a.entries[0].afterHash)
            _ = try await h.changes.undo(id: b.id, actor: .user)
            #expect(try await h.notes.open(id: "bio/glossary").text == "# Glossary\n\none\n")
            _ = try await h.changes.undo(id: a.id, actor: .user)
            let end = try await h.notes.open(id: "bio/glossary")
            #expect(end.text == v0.text && end.version == v0.version)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aStrictUndoRefusesWhenTheNoteChangedSinceAndChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let a = try await save(h, "bio/glossary", "# Glossary\n\none\n", base: v0.version)
            let b = try await save(h, "bio/glossary", "# Glossary\n\ntwo\n", base: a.entries[0].afterHash)
            let before = try await h.notes.open(id: "bio/glossary")
            let listed = try await changeIDs(h).count
            do {
                _ = try await h.changes.undo(id: a.id, actor: .user)
                Issue.record("undo of an overwritten change must refuse")
            } catch let e as MarginError {
                #expect(e.code == "conflict")
                #expect(e.conflictDetail?.currentVersion == b.entries[0].afterHash)
            }
            let after = try await h.notes.open(id: "bio/glossary")
            #expect(after == before)
            #expect(try await changeIDs(h).count == listed)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aChangeSetCanOnlyBeUndoneOnce(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let cs = try await save(h, "bio/glossary", "# Glossary\n\nchanged\n", base: v0.version)
            _ = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(await code { try await h.changes.undo(id: cs.id, actor: .user) } == "conflict")
            #expect(try await h.notes.open(id: "bio/glossary").version == v0.version)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func anUnknownChangeSetIsNotFound(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            #expect(await code { try await h.changes.undo(id: "cs-nope", actor: .user) } == "notFound")
            #expect(await code { try await h.changes.change(id: "cs-nope") } == "notFound")
            let listed = try await changeIDs(h)
            #expect(listed.isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aDryRunUndoChangesNothingAndRecordsNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let cs = try await save(h, "bio/glossary", "# Glossary\n\nchanged\n", base: v0.version)
            let now = try await h.notes.open(id: "bio/glossary")
            let dry = try await h.changes.undo(id: cs.id, actor: .user, mode: .strict, dryRun: true)
            #expect(dry.isDryRun && dry.revertsID == cs.id && dry.entries.count == 1)
            #expect(dry.entries[0].afterHash == v0.version)
            #expect(try await h.notes.open(id: "bio/glossary") == now)
            #expect(try await changeIDs(h) == [cs.id])
            // A dry run still detects conflicts.
            _ = try await save(h, "bio/glossary", "# Glossary\n\nmore\n", base: now.version)
            #expect(await code { try await h.changes.undo(id: cs.id, actor: .user, mode: .strict, dryRun: true) } == "conflict")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aMergeUndoKeepsLaterEditsInOtherPlaces(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let id = try await sandbox(h)
            let v0 = try await h.notes.open(id: id)
            let a = try await save(h, id, replacing(2, with: "EARLY EDIT"), base: v0.version)                  // change to undo
            let late = replacing(11, with: "LATE EDIT", in: replacing(2, with: "EARLY EDIT"))
            _ = try await save(h, id, late, base: a.entries[0].afterHash)                                        // later edit, elsewhere
            // Strict refuses...
            #expect(await code { try await h.changes.undo(id: a.id, actor: .user) } == "conflict")
            // ...merge undoes only the early edit.
            let undo = try await h.changes.undo(id: a.id, actor: .user, mode: .merge, dryRun: false)
            #expect(undo.entries.first?.merged == true)
            #expect(try await h.notes.open(id: id).text == replacing(11, with: "LATE EDIT"))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aMergeUndoStillRefusesOverlappingEditsAndShowsMarkers(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let id = try await sandbox(h)
            let v0 = try await h.notes.open(id: id)
            let a = try await save(h, id, replacing(5, with: "FIRST"), base: v0.version)
            let b = try await save(h, id, replacing(5, with: "SECOND"), base: a.entries[0].afterHash)
            let before = try await h.notes.open(id: id)
            do {
                _ = try await h.changes.undo(id: a.id, actor: .user, mode: .merge, dryRun: false)
                Issue.record("overlapping undo must refuse")
            } catch let e as MarginError {
                #expect(e.code == "conflict")
                let detail = try #require(e.conflictDetail)
                #expect(detail.currentVersion == b.entries[0].afterHash)
                #expect(detail.conflictCount == 1)
                let merged = try #require(detail.mergedText)
                #expect(merged.contains("<<<<<<<") && merged.contains("=======") && merged.contains(">>>>>>>"))
                #expect(merged.contains("line 5") && merged.contains("SECOND"))
            }
            #expect(try await h.notes.open(id: id) == before)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingACreateRefusesWhenTheNoteWasEditedSince(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.notes.create(course: "bio", title: "Fresh note", kind: .note, text: "body\n", actor: .user,
                                              baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let id = try #require(cs.entries.first?.noteID)
            try await save(h, id, "body\nmore\n", base: nil)
            #expect(await code { try await h.changes.undo(id: cs.id, actor: .user) } == "conflict")
            #expect(await code { try await h.changes.undo(id: cs.id, actor: .user, mode: .merge, dryRun: false) } == "conflict")
            #expect(try await h.notes.open(id: id).text == "body\nmore\n")   // the user's later text survives
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingADeleteRefusesWhenTheNoteWasRecreated(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.notes.delete(id: "bio/glossary", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            _ = try await h.notes.create(course: "bio", title: "Glossary", kind: .note, text: "new glossary\n", actor: .user,
                                         baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(await code { try await h.changes.undo(id: cs.id, actor: .user) } == "conflict")
            #expect(try await h.notes.open(id: "bio/glossary").text == "new glossary\n")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingAMoveRefusesWhenTheNoteMovedAgain(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let a = try await h.notes.move(id: "bio/glossary", toCourse: "chem", actor: .user, baseVersion: nil,
                                           dryRun: false, idempotencyKey: nil)
            _ = try await h.notes.move(id: "bio/glossary", toCourse: "math", actor: .user, baseVersion: nil,
                                       dryRun: false, idempotencyKey: nil)
            #expect(await code { try await h.changes.undo(id: a.id, actor: .user) } == "conflict")
            #expect(try await h.notes.open(id: "bio/glossary").summary.courseID == "math")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingAMoveStillWorksAfterTheMovedNoteWasEdited(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.notes.move(id: "bio/glossary", toCourse: "chem", actor: .user, baseVersion: nil,
                                            dryRun: false, idempotencyKey: nil)
            let moved = try await h.notes.open(id: "bio/glossary")
            try await save(h, "bio/glossary", "# Glossary\n\nedited after the move\n", base: moved.version)
            _ = try await h.changes.undo(id: cs.id, actor: .user)      // only the location is undone
            let back = try await h.notes.open(id: "bio/glossary")
            #expect(back.summary.courseID == "bio" && back.text == "# Glossary\n\nedited after the move\n")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingOneNoteDoesNotTouchAnother(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let g0 = try await h.notes.open(id: "bio/glossary")
            let l0 = try await h.notes.open(id: "bio/lecture-7")
            let a = try await save(h, "bio/glossary", "# Glossary\n\nchanged\n", base: g0.version)
            _ = try await save(h, "bio/lecture-7", "# Lecture 7 — Organelles\n\nchanged too\n", base: l0.version)
            _ = try await h.changes.undo(id: a.id, actor: .user)
            #expect(try await h.notes.open(id: "bio/glossary").version == g0.version)
            #expect(try await h.notes.open(id: "bio/lecture-7").text == "# Lecture 7 — Organelles\n\nchanged too\n")
        }
    }

    // MARK: Listing and recording

    @Test(arguments: HarnessKind.allCases)
    func anUndoIsRecordedWithItsActorAndListedFirst(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let cs = try await save(h, "bio/glossary", "# Glossary\n\nchanged\n", base: v0.version, actor: testActor)
            let undo = try await h.changes.undo(id: cs.id, actor: .system)
            let all = try await h.changes.changes()
            #expect(all.map(\.id) == [undo.id, cs.id])
            #expect(all[0].actor == .system && all[1].actor == testActor)
            #expect(all[0].revertsID == cs.id && all[1].revertsID == nil)
            #expect(try await h.changes.change(id: cs.id) == cs)
            #expect(try await h.changes.change(id: undo.id) == undo)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func changesAreListedNewestFirstAndCanBeLimited(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            var ids: [String] = []
            var base = try await h.notes.open(id: "bio/glossary").version
            for i in 1...5 {
                let cs = try await save(h, "bio/glossary", "# Glossary\n\nv\(i)\n", base: base)
                base = try #require(cs.entries[0].afterHash)
                ids.append(cs.id)
            }
            let all = try await h.changes.changes()
            #expect(all.map(\.id) == ids.reversed())
            #expect(try await changeIDs(h, limit: 2) == Array(ids.reversed().prefix(2)))
            #expect(try await changeIDs(h, limit: 0).isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func dryRunsFailedWritesAndNoOpsAreNotRecorded(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            _ = try await save(h, "bio/glossary", "# Glossary\n\ndry\n", base: v0.version, dryRun: true)
            _ = try await save(h, "bio/glossary", v0.text, base: v0.version)                            // identical text
            #expect(await code { try await save(h, "bio/glossary", "x", base: "stale") } == "conflict")
            #expect(await code { try await h.notes.move(id: "bio/glossary", toCourse: "nope", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "notFound")
            _ = try await h.notes.move(id: "bio/glossary", toCourse: "chem", actor: .user, baseVersion: nil, dryRun: true, idempotencyKey: nil)
            _ = try await h.notes.delete(id: "bio/glossary", actor: .user, baseVersion: nil, dryRun: true, idempotencyKey: nil)
            #expect(try await changeIDs(h).isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aRetriedWriteWithTheSameKeyIsRecordedOnce(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let first = try await save(h, "bio/glossary", "# Glossary\n\nonce\n", base: v0.version, key: "k-1")
            let second = try await save(h, "bio/glossary", "# Glossary\n\nonce\n", base: v0.version, key: "k-1")
            #expect(first == second)
            #expect(try await changeIDs(h) == [first.id])
        }
    }

    // MARK: Retention

    @Test(arguments: HarnessKind.allCases)
    func aChangeSetExpiresAfterThirtyDays(kind: HarnessKind) async throws {
        let clock = MutableClock()
        try await withHarness(kind, clock: clock) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let old = try await save(h, "bio/glossary", "# Glossary\n\nold\n", base: v0.version)
            clock.advance(bySeconds: 10 * 86_400)
            let mid = try await save(h, "bio/glossary", "# Glossary\n\nmid\n", base: old.entries[0].afterHash)
            // 30 days after `old` exactly: still kept.
            clock.advance(bySeconds: 20 * 86_400)
            #expect(try await changeIDs(h) == [mid.id, old.id])
            // One second more and `old` is gone, `mid` (20 days old) stays.
            clock.advance(bySeconds: 1)
            #expect(try await changeIDs(h) == [mid.id])
            #expect(await code { try await h.changes.undo(id: old.id, actor: .user) } == "notFound")
            #expect(await code { try await h.changes.change(id: old.id) } == "notFound")
            // The kept one can still be undone (its file state is intact).
            _ = try await h.changes.undo(id: mid.id, actor: .user)
            #expect(try await h.notes.open(id: "bio/glossary").text == "# Glossary\n\nold\n")
            // And a new write after a long time prunes what expired by then.
            clock.advance(bySeconds: 31 * 86_400)
            let v = try await h.notes.open(id: "bio/glossary")
            let fresh = try await save(h, "bio/glossary", "# Glossary\n\nfresh\n", base: v.version)
            #expect(try await changeIDs(h) == [fresh.id])
        }
    }

    /// The vault's journal is checked at the same size, with its files on disk, by
    /// `ConcurrentWriterStressTests` (2000 saves, 500 kept): five hundred real writes here would only
    /// slow down the timing tests that run next to this suite.
    @Test(arguments: [HarnessKind.fixture])
    func onlyTheNewestFiveHundredChangeSetsAreKept(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            var ids: [String] = []
            var base = try await h.notes.open(id: "bio/glossary").version
            for i in 1...503 {
                let cs = try await save(h, "bio/glossary", "# Glossary\n\nv\(i)\n", base: base)
                base = try #require(cs.entries[0].afterHash)
                ids.append(cs.id)
            }
            let all = try await h.changes.changes()
            #expect(all.count == 500)
            #expect(all.map(\.id) == Array(ids.suffix(500).reversed()))
            #expect(await code { try await h.changes.undo(id: ids[0], actor: .user) } == "notFound")
            #expect(await code { try await h.changes.undo(id: ids[2], actor: .user) } == "notFound")
            // The newest can be undone; the 500th-newest is the oldest that still exists.
            _ = try await h.changes.undo(id: ids[502], actor: .user)
            #expect(try await h.notes.open(id: "bio/glossary").text == "# Glossary\n\nv502\n")
            #expect(try await changeIDs(h).count == 500)      // the undo took the place of the oldest
        }
    }

    // MARK: Concurrency: baseVersion and three-way merge (AG-04)

    @Test(arguments: HarnessKind.allCases)
    func aStaleSaveThatTouchesOtherLinesIsMerged(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let id = try await sandbox(h)
            let v0 = try await h.notes.open(id: id)                                     // both writers start here
            let theirs = try await save(h, id, replacing(11, with: "THEIR LINE"), base: v0.version, actor: .user)
            // The second writer still holds v0 and changed line 2 only.
            let cs = try await save(h, id, replacing(2, with: "MY LINE"), base: v0.version, actor: testActor)
            #expect(cs.entries.count == 1 && cs.entries[0].merged == true)
            #expect(cs.entries[0].beforeHash == theirs.entries[0].afterHash)            // it replaced their version
            let now = try await h.notes.open(id: id)
            #expect(now.text == replacing(11, with: "THEIR LINE", in: replacing(2, with: "MY LINE")))
            #expect(cs.entries[0].afterHash == now.version)
            // The merged save is a change set like any other.
            _ = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(try await h.notes.open(id: id).text == replacing(11, with: "THEIR LINE"))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aStaleSaveThatOverlapsIsAConflictWithMarkersAndTheCurrentVersion(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let id = try await sandbox(h)
            let v0 = try await h.notes.open(id: id)
            let theirs = try await save(h, id, replacing(6, with: "THEIRS"), base: v0.version, actor: .user)
            let current = try await h.notes.open(id: id)
            do {
                _ = try await save(h, id, replacing(6, with: "MINE"), base: v0.version, actor: testActor)
                Issue.record("overlapping stale save must conflict")
            } catch let e as MarginError {
                #expect(e.code == "conflict")
                let detail = try #require(e.conflictDetail)
                #expect(detail.currentVersion == theirs.entries[0].afterHash)
                #expect(detail.conflictCount == 1)
                let merged = try #require(detail.mergedText)
                #expect(merged.contains("<<<<<<< yours\nMINE\n=======\nTHEIRS\n>>>>>>> "))
                // Everything outside the conflict is intact.
                #expect(merged.hasPrefix("line 1\nline 2\nline 3\nline 4\nline 5\n<<<<<<<"))
                #expect(merged.hasSuffix(">>>>>>> \(kind == .vault ? "stored" : "stored")\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\n"))
            }
            #expect(try await h.notes.open(id: id) == current)                          // nothing was written
            // The caller resolves and retries with the version from the error.
            let resolved = try await save(h, id, replacing(6, with: "MINE AND THEIRS"), base: current.version)
            #expect(resolved.entries[0].merged == nil)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aBaseVersionThatCannotBeReconstructedIsAPlainConflictWithTheCurrentVersion(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let id = try await sandbox(h)
            let current = try await h.notes.open(id: id)
            do {
                _ = try await save(h, id, replacing(2, with: "x"), base: "0000-not-a-version")
                Issue.record("unknown base must conflict")
            } catch let e as MarginError {
                #expect(e.code == "conflict")
                #expect(e.conflictDetail?.currentVersion == current.version)
                #expect(e.conflictDetail?.mergedText == nil)
            }
            #expect(try await h.notes.open(id: id) == current)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func moveAndDeleteWithAStaleBaseConflictWithoutMerging(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let cs = try await save(h, "bio/glossary", "# Glossary\n\nchanged\n", base: v0.version)
            for op in 0..<2 {
                do {
                    if op == 0 {
                        _ = try await h.notes.move(id: "bio/glossary", toCourse: "chem", actor: .user, baseVersion: v0.version,
                                                   dryRun: false, idempotencyKey: nil)
                    } else {
                        _ = try await h.notes.delete(id: "bio/glossary", actor: .user, baseVersion: v0.version,
                                                     dryRun: false, idempotencyKey: nil)
                    }
                    Issue.record("stale base must conflict")
                } catch let e as MarginError {
                    #expect(e.code == "conflict")
                    #expect(e.conflictDetail?.currentVersion == cs.entries[0].afterHash)
                }
            }
            #expect(try await h.notes.open(id: "bio/glossary").summary.courseID == "bio")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aSaveWithoutBaseVersionStillWinsAndCanBeUndone(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let cs = try await save(h, "bio/glossary", "# Glossary\n\nlast writer\n", base: nil)
            #expect(cs.entries[0].merged == nil)
            _ = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(try await h.notes.open(id: "bio/glossary").version == v0.version)
        }
    }

    // MARK: Other writers of the services (tasks, properties)

    @Test(arguments: HarnessKind.allCases)
    func undoingATaskToggleRestoresTheFileByteForByte(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = "bio/assignments"
            let before = try await h.rawContent(note)
            let cs = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: testActor, baseVersion: nil, dryRun: false,
                                              idempotencyKey: nil)
            #expect(try await h.rawContent(note) != before)
            let undo = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(try await h.rawContent(note) == before)
            #expect(undo.entries.first?.noteID == note)
            // The task list follows: the task is done again.
            let item = try #require(try await h.tasks.tasks(course: "bio").first { $0.id == "task-bio-read-chapter-6" })
            #expect(item.done)
            // Redo.
            _ = try await h.changes.undo(id: undo.id, actor: .user)
            #expect(try await h.rawContent(note) != before)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func undoingAPropertyChangeRestoresTheFrontmatterByteForByte(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = "bio/lecture-8"
            let before = try await h.rawContent(note)
            let cs = try await h.properties.set(key: "difficulty", value: .number(3), on: note, actor: testActor,
                                                baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(try await h.rawContent(note) != before)
            #expect(try await h.changes.changes().first == cs)
            _ = try await h.changes.undo(id: cs.id, actor: .user)
            #expect(try await h.rawContent(note) == before)
            let removal = try await h.properties.remove(key: "type", on: note, actor: .user, baseVersion: nil, dryRun: false,
                                                        idempotencyKey: nil)
            #expect(try await h.rawContent(note) != before)
            _ = try await h.changes.undo(id: removal.id, actor: .user)
            #expect(try await h.rawContent(note) == before)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aTaskToggleAndADryRunToggleAreRecordedCorrectly(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: .user, baseVersion: nil, dryRun: true, idempotencyKey: nil)
            let none = try await changeIDs(h)
            #expect(none.isEmpty)
            let first = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: .user, baseVersion: nil, dryRun: false,
                                                 idempotencyKey: "t-1")
            let again = try await h.tasks.toggle(id: "task-bio-read-chapter-6", actor: .user, baseVersion: nil, dryRun: false,
                                                 idempotencyKey: "t-1")
            #expect(first == again)
            let listed = try await changeIDs(h)
            #expect(listed == [first.id])
        }
    }
}
