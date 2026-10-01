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

@Suite struct LinkAnchorTests {
    private let text = "# Buňka\n\n## Membrána\nText ^m1\n\n### Transport přes membránu\n- osmóza ^osm\n"

    @Test func headingsMatchWithoutMarksOrCase() {
        #expect(LinkAnchor.line(of: "membrána", in: text) == 2)
        #expect(LinkAnchor.line(of: "Membrána#Transport přes membránu", in: text) == 5)
        #expect(LinkAnchor.line(of: "Chybí", in: text) == nil)
    }

    @Test func blockIDsMatchTheEndOfALine() {
        #expect(LinkAnchor.line(of: "^osm", in: text) == 6)
        #expect(LinkAnchor.line(of: "^M1", in: text) == 3)
        #expect(LinkAnchor.line(of: "^none", in: text) == nil)
    }
}

@Suite struct ImageEmbedTests {
    @Test func parsesBothSyntaxes() {
        #expect(ImageEmbed.parse("![[bilayer.png|300]]")?.name == "bilayer.png")
        #expect(ImageEmbed.parse("![[bilayer.png|300]]")?.width == "300")
        let md = ImageEmbed.parse("Viz ![Membrána|200](obr/cell%20a.png) níže")
        #expect(md?.name == "obr/cell a.png" && md?.width == "200" && md?.wiki == false)
        #expect(ImageEmbed.parse("[[odkaz]]") == nil)
    }

    @Test func resizingRewritesOnlyTheWidth() {
        let wiki = "![[bilayer.png|300]]"
        #expect(ImageEmbed.parse(wiki)!.resized(640, in: wiki) == "![[bilayer.png|640]]")
        #expect(ImageEmbed.parse(wiki)!.resized(nil, in: wiki) == "![[bilayer.png]]")
        let md = "Viz ![Membrána](cell.png)"
        #expect(ImageEmbed.parse(md)!.resized(200, in: md) == "Viz ![Membrána|200](cell.png)")
        let sized = "![Membrána|200](cell.png)"
        #expect(ImageEmbed.parse(sized)!.resized(nil, in: sized) == "![Membrána](cell.png)")
    }
}

/// Vision loads its text model on first use (tens of seconds): a slow tier in `scripts/test-tiers.txt`.
@Suite struct ImageTextRecognitionTests {
    @Test func recognizesTextInAPicture() async throws {
        let image = NSImage(size: NSSize(width: 600, height: 120), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Fosfolipidová dvojvrstva" as NSString).draw(at: NSPoint(x: 20, y: 40), withAttributes: [.font: NSFont.systemFont(ofSize: 40)])
            return true
        }
        let data = try #require(image.tiffRepresentation)
        let lines = await ImageActions.recognizeText(in: data)
        #expect(lines.joined(separator: " ").lowercased().contains("dvojvrstva"))
    }
}

@Suite struct CurrentBlockTests {
    @Test func detectsTheBlockOfTheCaretLine() {
        let text = "# Titul\n## Část\nOdstavec\n> [!tip] Rada\n> tělo\n> citát\n```\nkód\n```\n- [ ] úkol\n"
        func at(_ s: String) -> EditorBlock { EditorHandle.block(at: (text as NSString).range(of: s).location, in: text) }
        #expect(at("Titul") == .heading1 && at("Část") == .heading2 && at("Odstavec") == .paragraph)
        #expect(at("Rada") == .callout && at("tělo") == .callout)
        #expect(at("kód") == .codeBlock && at("úkol") == .checklist)
        #expect(EditorHandle.block(at: 0, in: "> jen citát\n") == .quote)
    }
}
