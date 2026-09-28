import Foundation
import Testing
@testable import MarginCore

@Suite struct NoteIndexStableIDTests {
    static let a = "---\nid: n-aaaa\n---\n# A\n\n- [ ] first ^t-1111\n- [ ] second ^t-2222\n- [x] third @2026-10-01 ^t-3333\n"
    static let b = "---\nid: n-bbbb\n---\n# B\n\n- [ ] other ^t-4444\n"

    func makeIndex(_ entries: [(String, String)]) async -> NoteIndex {
        let index = NoteIndex(clock: FixedClock())
        await index.build(entries: entries.map { (path: $0.0, content: $0.1) })
        return index
    }

    @Test func usesFrontmatterIDAndBlockIDs() async throws {
        let index = await makeIndex([("fall/bio/A.md", Self.a)])
        let n = try #require(await index.note(byPath: "fall/bio/A.md"))
        #expect(n.id == "n-aaaa" && n.hasStableID && n.tasksWithoutID == 0 && !n.needsIDAssignment)
        #expect(n.tasks.map(\.id) == ["t-1111", "t-2222", "t-3333"])
        #expect(await index.note(byID: "n-aaaa")?.path == "fall/bio/A.md")
        #expect(await index.task(byID: "t-2222")?.text == "second")
        #expect(await index.task(byID: "t-2222")?.source == TaskLocation(noteID: "n-aaaa", line: 7, courseID: "bio"))
    }

    @Test func placeholdersAreUsedUntilIDsAreAssigned() async throws {
        let index = await makeIndex([("fall/bio/Plain.md", "# P\n- [ ] one\n- [ ] two ^t-9999\n")])
        let n = try #require(await index.note(byPath: "fall/bio/Plain.md"))
        #expect(n.id == "fall/bio/Plain" && !n.hasStableID && n.tasksWithoutID == 1 && n.needsIDAssignment)
        #expect(n.tasks.map(\.id) == ["fall/bio/Plain#L2", "t-9999"])
        #expect(StableIDGenerator.isPlaceholderTaskID(n.tasks[0].id))
        #expect(await index.notesNeedingIDs().map(\.path) == ["fall/bio/Plain.md"])
    }

    @Test func emptyOrNullIDIsNotStable() async throws {
        let index = await makeIndex([("x.md", "---\nid:\n---\nbody\n"), ("y.md", "---\nid: \"\"\n---\nbody\n")])
        for p in ["x.md", "y.md"] {
            let n = try #require(await index.note(byPath: p))
            #expect(!n.hasStableID && n.id == String(p.dropLast(3)))
        }
    }

    @Test func taskKeepsIdentityWhenItsTextIsEdited() async throws {
        let index = await makeIndex([("fall/bio/A.md", Self.a)])
        let edited = Self.a.replacingOccurrences(of: "second", with: "second, rewritten completely @Fri")
        await index.update(path: "fall/bio/A.md", content: edited)
        let t = try #require(await index.task(byID: "t-2222"))
        #expect(t.text == "second, rewritten completely")
        #expect(t.due != nil)
        #expect(t.source.line == 7)
    }

    @Test func taskKeepsIdentityWhenTasksAreReordered() async throws {
        let index = await makeIndex([("fall/bio/A.md", Self.a)])
        let reordered = "---\nid: n-aaaa\n---\n# A\n\n- [x] third @2026-10-01 ^t-3333\n- [ ] second ^t-2222\nNew paragraph.\n- [ ] first ^t-1111\n"
        await index.update(path: "fall/bio/A.md", content: reordered)
        #expect(await index.task(byID: "t-1111")?.source.line == 9)
        #expect(await index.task(byID: "t-2222")?.source.line == 7)
        #expect(await index.task(byID: "t-3333")?.source.line == 6)
        #expect(await index.task(byID: "t-3333")?.done == true)
    }

    @Test func taskIDTravelsWithTheLineToAnotherNote() async throws {
        let index = await makeIndex([("fall/bio/A.md", Self.a), ("fall/chem/B.md", Self.b)])
        await index.update(path: "fall/bio/A.md", content: "---\nid: n-aaaa\n---\n# A\n\n- [ ] first ^t-1111\n- [x] third @2026-10-01 ^t-3333\n")
        await index.update(path: "fall/chem/B.md", content: Self.b + "- [ ] second ^t-2222\n")
        let t = try #require(await index.task(byID: "t-2222"))
        #expect(t.source.noteID == "n-bbbb")
        #expect(t.source.courseID == "chem")
        #expect(t.source.line == 7)
        #expect(await index.duplicateTaskIDs().isEmpty)
    }

    @Test func noteRenameAndMoveKeepNoteAndTaskIDs() async throws {
        let index = await makeIndex([("fall/bio/A.md", Self.a)])
        #expect(await index.rename(from: "fall/bio/A.md", to: "fall/bio/Renamed.md"))
        #expect(await index.rename(from: "fall/bio/Renamed.md", to: "spring/chem/deep/Moved.md"))
        let n = try #require(await index.note(byID: "n-aaaa"))
        #expect(n.path == "spring/chem/deep/Moved.md")
        #expect(n.courseID == "chem" && n.semesterID == "spring")
        #expect(n.tasks.map(\.id) == ["t-1111", "t-2222", "t-3333"])
        #expect(n.tasks.allSatisfy { $0.source.noteID == "n-aaaa" })
        #expect(await index.task(byID: "t-1111")?.source.courseID == "chem")
    }

    @Test func duplicateIDsAreDetectedAndTheFirstByPathWins() async throws {
        let index = await makeIndex([
            ("z/late.md", "---\nid: n-same\n---\n- [ ] late copy ^t-dupe\n"),
            ("a/early.md", "---\nid: n-same\n---\n- [ ] early ^t-dupe\n- [ ] early again ^t-dupe\n"),
        ])
        #expect(await index.task(byID: "t-dupe")?.text == "early")
        let dups = await index.duplicateTaskIDs()
        #expect(dups.count == 1)
        #expect(dups[0].locations == [IDOccurrence(path: "a/early.md", line: 4), IDOccurrence(path: "a/early.md", line: 5),
                                      IDOccurrence(path: "z/late.md", line: 4)])
        #expect(await index.note(byID: "n-same")?.path == "a/early.md")
        #expect(await index.duplicateNoteIDs() == [DuplicateID(id: "n-same", locations: [
            IDOccurrence(path: "a/early.md", line: nil), IDOccurrence(path: "z/late.md", line: nil)])])
    }

    @Test func removingANoteForgetsItsTaskIDs() async throws {
        let index = await makeIndex([("a.md", Self.a), ("b.md", Self.b)])
        #expect(await index.remove(path: "a.md"))
        #expect(await index.task(byID: "t-1111") == nil)
        #expect(await index.task(byID: "t-4444") != nil)
        // Re-adding the same ids in another file works, and updating a note twice does not leak entries.
        await index.update(path: "c.md", content: Self.a.replacingOccurrences(of: "n-aaaa", with: "n-cccc"))
        await index.update(path: "c.md", content: Self.a.replacingOccurrences(of: "n-aaaa", with: "n-cccc") + "\n- [ ] x ^t-5555\n")
        #expect(await index.duplicateTaskIDs().isEmpty)
        #expect(await index.task(byID: "t-1111")?.source.noteID == "n-cccc")
    }

    @Test func assignedTextIndexesWithoutPlaceholders() async throws {
        let raw = "# Notes\n\n- [ ] alpha\n  - [ ] beta @Tue\n```\n- [ ] code\n```\n- [x] gamma\n"
        var g = makeGenerator(5)
        let assigned = IDAssigner().assign(to: raw, generator: &g)
        let index = await makeIndex([("fall/bio/Notes.md", assigned.text)])
        let n = try #require(await index.note(byPath: "fall/bio/Notes.md"))
        #expect(n.id == assigned.noteID)
        #expect(n.tasks.count == 3)
        #expect(n.tasks.map(\.id) == assigned.tasks.map(\.id))
        #expect(n.tasks.allSatisfy { !StableIDGenerator.isPlaceholderTaskID($0.id) })
        #expect(!n.needsIDAssignment)
    }
}
