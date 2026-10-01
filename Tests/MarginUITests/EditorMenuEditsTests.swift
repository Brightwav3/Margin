import AppKit
import MarginCore
import Testing
@testable import MarginUI

/// Text edits behind the editor menus (Margin Menus 1g, 1i, 1m).
@MainActor @Suite struct EditorMenuEditsTests {
    let table = ["| Transport | Energy |", "| --- | --- |", "| Passive | None |", "| Active | ATP |"]

    @Test func tableRowsAndColumns() {
        #expect(TableEditing.apply(.insertRow(above: false), to: table, row: 2, column: 0)
                == ["| Transport | Energy |", "| --- | --- |", "| Passive | None |", "|  |  |", "| Active | ATP |"])
        #expect(TableEditing.apply(.insertColumn(left: false), to: table, row: 2, column: 0)[0] == "| Transport |  | Energy |")
        #expect(TableEditing.apply(.insertColumn(left: false), to: table, row: 2, column: 0)[1] == "| --- | --- | --- |")
        #expect(TableEditing.apply(.deleteRow, to: table, row: 3, column: 0).count == 3)
        #expect(TableEditing.apply(.deleteRow, to: table, row: 1, column: 0) == table, "the delimiter line stays")
        #expect(TableEditing.apply(.deleteColumn, to: table, row: 2, column: 1)[2] == "| Passive |")
        #expect(TableEditing.apply(.sort(ascending: true), to: table, row: 2, column: 0)[2] == "| Active | ATP |")
        #expect(TableEditing.apply(.align(.center), to: table, row: 0, column: 1)[1] == "| --- | :-: |")
        #expect(TableEditing.cells("a | b \\| c") == ["a", "b \\| c"])
    }

    @Test func tagsAreFoundAndRewrittenOnlyAsWholeTags() {
        #expect(TagEditing.normalized("exam") == "#exam" && TagEditing.normalized("#a b") == nil && TagEditing.normalized("#12") == nil)
        let text = "#exam prep and #examples, also #exam/2 and #exam.\n- [ ] Read #exam"
        #expect(TagEditing.replace("#exam", with: "#test", in: text) == "#test prep and #examples, also #exam/2 and #test.\n- [ ] Read #test")
        #expect(TagEditing.replace("#exam", with: nil, in: "Read #exam now") == "Read now")
        #expect(MarginTextView.tag(in: "Read #exam now" as NSString, at: 7) == "#exam")
        #expect(MarginTextView.tag(in: "Read #exam now" as NSString, at: 2) == nil)
        #expect(MarginTextView.tag(in: "## Heading" as NSString, at: 4) == nil)
    }

    @Test func aSectionRunsToTheNextHeadingOfItsLevel() {
        let text = "# Note\n## A\none\n### A.1\ntwo\n## B\nthree\n" as NSString
        let a = EditorMenus.sectionRange(at: 8, in: text)
        #expect(a?.level == 2 && text.substring(with: a!.range) == "## A\none\n### A.1\ntwo\n")
        #expect(EditorMenus.firstLine("## Osmosis is diffusion\nmore") == "Osmosis is diffusion")
        let link = EditorMenus.wikilink(at: 7, in: "See [[Membrane transport|transport]] now" as NSString)
        #expect(link?.target == "Membrane transport" && link?.alias == "transport")
    }

    @Test func workspaceNoteActions() async throws {
        let w = Workspace(env: .fixture())
        await w.courses.load()
        let note = try #require(try await w.env.notes.notes(course: "math").first)
        w.duplicate(note)
        var copies: [NoteSummary] = []
        for _ in 0..<100 where copies.isEmpty {
            copies = try await w.env.notes.notes(course: "math").filter { $0.title == note.title + " copy" }
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(copies.count == 1, "\(String(describing: w.toast))")
        _ = try await w.env.notes.rename(id: note.id, to: "Renamed note", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(try await w.env.notes.open(id: note.id).summary.title == "Renamed note")
    }
}
