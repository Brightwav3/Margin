import AppKit
import MarginCore
import Testing
@testable import MarginUI

/// 1r: several notes selected in a list, and what their menu does.
@MainActor @Suite struct MultiSelectTests {
    private func notes(_ w: Workspace) async throws -> [NoteSummary] {
        Array(try await w.env.notes.notes(course: "bio").sorted { $0.title < $1.title }.prefix(3))
    }

    private func settle(until done: () async -> Bool) async {
        for _ in 0..<100 { if await done() { return }; try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func commandAndShiftClicksBuildTheSelection() async throws {
        let w = Workspace(env: .fixture())
        let list = try await notes(w)
        var opened = 0
        w.click(note: list[0], in: list, modifiers: []) { opened += 1 }
        #expect(opened == 1 && w.noteSelection.isEmpty)
        w.click(note: list[2], in: list, modifiers: .shift) {}
        #expect(w.noteSelection.map(\.id) == list.map(\.id))
        w.click(note: list[1], in: list, modifiers: .command) {}
        #expect(w.noteSelection.map(\.id) == [list[0].id, list[2].id])
        w.click(note: list[1], in: list, modifiers: []) { opened += 1 }
        #expect(opened == 2 && w.noteSelection.isEmpty)
    }

    @Test func mergeKeepsTheFirstAndAppendsTheOthers() async throws {
        let w = Workspace(env: .fixture())
        let list = Array(try await notes(w).prefix(2))
        w.merge(list)
        await settle { (try? await w.env.notes.notes(course: "bio").contains { $0.id == list[1].id }) == false }
        let merged = try await w.env.notes.open(id: list[0].id).text
        #expect(merged.contains("## \(list[1].title)"))
        #expect(try await !w.env.notes.notes(course: "bio").contains { $0.id == list[1].id })
    }

    @Test func tagsAreAddedToEveryNote() async throws {
        let w = Workspace(env: .fixture())
        let list = try await notes(w)
        w.addTag("#zkouska", to: list)
        await settle {
            guard let p = try? await w.env.analysis.properties(id: list[2].id) else { return false }
            if case .list(let tags)? = p.first(where: { $0.key == "tags" })?.value { return tags.contains(.string("zkouska")) }
            return false
        }
        for note in list {
            let p = try await w.env.analysis.properties(id: note.id)
            guard case .list(let tags)? = p.first(where: { $0.key == "tags" })?.value else { Issue.record("no tags"); continue }
            #expect(tags.contains(.string("zkouska")))
        }
    }

    @Test func combinedMarkdownPutsEachNoteUnderItsTitle() {
        let text = Workspace.combined([("A", "# A\n\nprvní"), ("B", "druhá")])
        #expect(text == "# A\n\nprvní\n\n# B\n\ndruhá")
    }
}
