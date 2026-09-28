import Foundation
import Testing
@testable import MarginCore

private struct MemorySource: NoteContentSource {
    let files: [String: String]
    func listMarkdown() async throws -> [String] { files.keys.sorted() }
    func read(_ path: String) async throws -> String {
        guard let t = files[path] else { throw MarginError.notFound(path) }
        return t
    }
}

private let bioNote = """
---
id: n-bio1
type: lecture
date: 2026-09-24
tags: [cells, exam]
---
# Cell Biology

Intro to [[Glossary]] and [[chem/Atoms|atoms]].

- [ ] Read chapter 2 @2026-10-01
- [x] Watch video
"""

private let glossary = "# Glossary\n\nTerms. See [[Missing Note]].\n\n- [ ] Learn terms\n"
private let atoms = "---\ntags: [#exam]\n---\nAtoms text with ![[diagram.png]] and [[Cell Biology]].\n"
private let loose = "---\nclass: \"[[Cell Biology]]\"\n---\nLoose note, [[Glossary]] again.\n"

private func vault() -> [(path: String, content: String)] {
    [("fall-2026/bio/Cell Biology.md", bioNote),
     ("fall-2026/bio/Glossary.md", glossary),
     ("fall-2026/chem/Atoms.md", atoms),
     ("Inbox/Loose.md", loose)]
}

private func makeIndex() async -> NoteIndex {
    let index = NoteIndex(clock: FixedClock())
    await index.build(entries: vault())
    return index
}

@Suite struct NoteIndexTests {
    @Test func buildsRecords() async throws {
        let index = await makeIndex()
        #expect(await index.count == 4)
        let n = try #require(await index.note(byPath: "fall-2026/bio/Cell Biology.md"))
        #expect(n.id == "n-bio1")
        #expect(n.title == "Cell Biology")
        #expect(n.courseID == "bio")
        #expect(n.semesterID == "fall-2026")
        #expect(n.kind == .lecture)
        #expect(n.tags == ["cells", "exam"])
        #expect(n.date == LocalDate(year: 2026, month: 9, day: 24))
        #expect(n.properties["type"] != nil)
        #expect(n.headings.map(\.text) == ["Cell Biology"])
        #expect(n.tasks.count == 2)
        #expect(n.links.count == 2)
        #expect(n.summary.openTasks == 1 && n.summary.totalTasks == 2)
        #expect(await index.note(byID: "n-bio1")?.path == n.path)
        let g = try #require(await index.note(byPath: "fall-2026/bio/Glossary.md"))
        #expect(g.id == "fall-2026/bio/Glossary")   // placeholder id
        let a = try #require(await index.note(byPath: "fall-2026/chem/Atoms.md"))
        #expect(a.title == "Atoms")                  // file name when there is no H1
        #expect(a.imageCount == 1)
        let l = try #require(await index.note(byPath: "Inbox/Loose.md"))
        #expect(l.courseID == "cell-biology")        // from class:
    }

    @Test func courseQueriesAndTasks() async {
        let index = await makeIndex()
        #expect(await index.notes(inCourse: "bio").map(\.title) == ["Cell Biology", "Glossary"])
        #expect(await index.tasks().count == 3)
        #expect(await index.tasks(inCourse: "bio").count == 3)
        #expect(await index.tasks(inCourse: "chem").isEmpty)
        let open = await index.openTasks()
        #expect(open.map(\.text) == ["Read chapter 2", "Learn terms"])
        #expect(open.first?.due == LocalDate(year: 2026, month: 10, day: 1))
        #expect(open.first?.source.courseID == "bio")
    }

    @Test func backlinksAndUnresolved() async throws {
        let index = await makeIndex()
        let g = await index.backlinks(to: "fall-2026/bio/Glossary")
        #expect(Set(g.map(\.sourcePath)) == ["fall-2026/bio/Cell Biology.md", "Inbox/Loose.md"])
        #expect(g.first { $0.sourcePath.hasPrefix("fall") }?.snippet.contains("Intro to") == true)
        #expect(g.first { $0.sourcePath.hasPrefix("fall") }?.line == 9)
        let atoms = await index.backlinks(to: "fall-2026/chem/Atoms")
        #expect(atoms.count == 1)          // via [[chem/Atoms|atoms]]
        #expect(await index.backlinks(to: "n-bio1").map(\.sourcePath) == ["fall-2026/chem/Atoms.md"])
        let unresolved = await index.unresolvedLinks()
        #expect(unresolved.map(\.target) == ["Missing Note"])
        #expect(unresolved.first?.sourcePath == "fall-2026/bio/Glossary.md")
    }

    @Test func tagsQueries() async {
        let index = await makeIndex()
        let tags = await index.tags()
        #expect(tags["exam"] == 2 && tags["cells"] == 1)
        #expect(await index.notes(withTag: "#exam").count == 2)
    }

    @Test func incrementalUpdateKeepsBacklinksConsistent() async throws {
        let index = await makeIndex()
        let path = "fall-2026/bio/Glossary.md"
        // Unchanged content is skipped.
        #expect(await index.update(path: path, content: glossary) == false)
        // New content: adds a link to Atoms, drops the missing link.
        let changed = "# Glossary\n\nSee [[Atoms]].\n- [x] Learn terms\n"
        #expect(await index.update(path: path, content: changed) == true)
        #expect(await index.unresolvedLinks().isEmpty)
        #expect(await index.backlinks(to: "fall-2026/chem/Atoms").count == 2)
        #expect(await index.openTasks().count == 1)
        // A new note makes a formerly unresolved link resolve.
        await index.update(path: path, content: glossary)
        #expect(await index.unresolvedLinks().count == 1)
        await index.update(path: "fall-2026/bio/Missing Note.md", content: "# Missing Note\n")
        #expect(await index.unresolvedLinks().isEmpty)
        #expect(await index.backlinks(to: "fall-2026/bio/Missing Note").count == 1)
    }

    @Test func removeDropsBacklinks() async {
        let index = await makeIndex()
        #expect(await index.remove(path: "Inbox/Loose.md"))
        #expect(await index.backlinks(to: "fall-2026/bio/Glossary").count == 1)
        #expect(await index.remove(path: "Inbox/Loose.md") == false)
        // Removing the target makes links unresolved.
        await index.remove(path: "fall-2026/bio/Glossary.md")
        #expect(await index.unresolvedLinks().map(\.target) == ["Glossary"])
        #expect(await index.note(byID: "fall-2026/bio/Glossary") == nil)
    }

    @Test func renameKeepsBacklinksAndRederivesCourse() async throws {
        let index = await makeIndex()
        #expect(await index.rename(from: "fall-2026/bio/Glossary.md", to: "fall-2026/chem/Terms.md"))
        #expect(await index.note(byPath: "fall-2026/bio/Glossary.md") == nil)
        let moved = try #require(await index.note(byPath: "fall-2026/chem/Terms.md"))
        #expect(moved.courseID == "chem")
        #expect(moved.tasks.first?.source.courseID == "chem")
        // [[Glossary]] links no longer resolve; [[Missing Note]] still does not.
        #expect(Set(await index.unresolvedLinks().map(\.target)) == ["Glossary", "Missing Note"])
        // Rename back restores them.
        #expect(await index.rename(from: "fall-2026/chem/Terms.md", to: "fall-2026/bio/Glossary.md"))
        #expect(await index.backlinks(to: "fall-2026/bio/Glossary").count == 2)
        #expect(await index.rename(from: "nope.md", to: "x.md") == false)
    }

    @Test func applyConsumesFileChanges() async throws {
        let files = ["a/b/One.md": "# One\n[[Two]]\n", "a/b/Two.md": "# Two\n"]
        let index = NoteIndex(clock: FixedClock())
        try await index.build(from: MemorySource(files: files))
        #expect(await index.count == 2)
        #expect(await index.backlinks(to: "a/b/Two").count == 1)

        // Point the index at a source with new state and feed watcher-style changes.
        let next = MemorySource(files: ["a/b/One.md": "# One\nno links\n", "a/b/Three.md": "# Three\n[[One]]\n"])
        let idx2 = NoteIndex(clock: FixedClock(), source: next)
        await idx2.build(entries: files.map { ($0.key, $0.value) })
        let failures = await idx2.apply([
            FileChange(path: "a/b/One.md", kind: .modified),
            FileChange(path: "a/b/Three.md", kind: .created),
            FileChange(path: "a/b/Two.md", kind: .deleted),
            FileChange(path: "a/b/ghost.md", kind: .modified),   // vanished before read
            FileChange(path: "a/_files/img.png", kind: .created),
        ])
        #expect(failures.isEmpty)
        #expect(await idx2.allNotes.map(\.path) == ["a/b/One.md", "a/b/Three.md"])
        #expect(await idx2.backlinks(to: "a/b/One").map(\.sourcePath) == ["a/b/Three.md"])
        #expect(await idx2.backlinks(to: "a/b/Two").isEmpty)
    }
}

// MARK: - Performance budgets

private struct IndexRNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

private func syntheticVault(count: Int, seed: UInt64 = 42) -> [(path: String, content: String)] {
    var rng = IndexRNG(state: seed)
    let words = ["cell", "membrane", "protein", "energy", "atom", "bond", "the", "of", "and", "reaction",
                 "theory", "lecture", "exam", "model", "study", "graph", "proof", "vector", "signal", "noise"]
    var out: [(String, String)] = []
    for i in 0..<count {
        let course = "course\(i % 8)"
        var body = "---\nid: n-\(i)\ntype: lecture\ndate: 2026-09-\(10 + i % 18)\ntags: [t\(i % 10), exam]\n---\n# Note \(i)\n\n"
        for p in 0..<6 {
            var line: [String] = []
            for _ in 0..<50 { line.append(words[rng.below(words.count)]) }
            body += line.joined(separator: " ")
            if p % 2 == 0 { body += " [[Note \(rng.below(count))]]" }
            if p == 3 { body += " [[missing \(rng.below(50))]]" }
            body += "\n\n"
        }
        body += "- [ ] Task A \(i) @2026-10-0\(1 + i % 9)\n- [x] Task B \(i)\n  - [ ] Sub task\n"
        out.append(("fall-2026/\(course)/Note \(i).md", body))
    }
    return out
}

@Suite struct NoteIndexPerformanceTests {
    #if DEBUG
    static let slack = 5.0   // debug builds in a Docker container are far slower than release
    #else
    static let slack = 1.0
    #endif

    @Test func thousandNotesBuildAndReindexWithinBudget() async throws {
        let entries = syntheticVault(count: 1000)
        let index = NoteIndex(clock: FixedClock())

        let t0 = ContinuousClock.now
        await index.build(entries: entries)
        let build = ContinuousClock.now - t0
        #expect(await index.count == 1000)

        // Reindex one changed file (worst case: it has links).
        let target = entries[500]
        let changed = target.content + "\n- [ ] Extra task [[Note 7]]\n"
        let t1 = ContinuousClock.now
        let didChange = await index.update(path: target.path, content: changed)
        let reindex = ContinuousClock.now - t1
        #expect(didChange)

        // Queries on the built index.
        let t2 = ContinuousClock.now
        let backlinks = await index.backlinks(to: "n-7")
        let unresolved = await index.unresolvedLinks()
        let query = ContinuousClock.now - t2
        #expect(!backlinks.isEmpty && !unresolved.isEmpty)

        let bs = Double(build.components.seconds) + Double(build.components.attoseconds) / 1e18
        let rs = Double(reindex.components.seconds) + Double(reindex.components.attoseconds) / 1e18
        let qs = Double(query.components.seconds) + Double(query.components.attoseconds) / 1e18
        print("NoteIndex perf (slack x\(Self.slack)): build 1000 notes = \(Int(bs * 1000)) ms, "
              + "reindex 1 file = \(String(format: "%.1f", rs * 1000)) ms, "
              + "backlinks+unresolved = \(Int(qs * 1000)) ms")
        #expect(bs < 1.0 * Self.slack, "build budget 1 s")
        #expect(rs < 0.030 * Self.slack, "reindex budget 30 ms")
    }
}
