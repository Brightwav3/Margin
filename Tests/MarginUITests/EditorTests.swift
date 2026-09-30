import AppKit
import MarginCore
import Testing
@testable import MarginUI

@MainActor @Suite struct MarkdownStylerTests {
    private func styled(_ text: String, _ mode: EditorMode, activeLine: Int? = nil) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let tokenizer = MarkdownTokenizer(text: text)
        var active: MarkdownRange?
        if let activeLine, let r = tokenizer.lineRange(activeLine) { active = r }
        MarkdownStyler.apply(to: storage, range: NSRange(location: 0, length: storage.length),
                             tokens: tokenizer.tokens, mode: mode, active: active)
        return storage
    }

    private func hidden(_ s: NSTextStorage, _ at: Int) -> Bool { s.attribute(.marginHidden, at: at, effectiveRange: nil) != nil }

    @Test func liveHidesSyntaxOutsideTheActiveBlock() {
        let s = styled("## Fluid mosaic\n\nText with **bold**\n", .live)
        #expect(hidden(s, 0) && hidden(s, 1) && hidden(s, 2))   // `## `
        #expect(!hidden(s, 3))
        let bold = ("## Fluid mosaic\n\nText with " as NSString).length
        #expect(hidden(s, bold) && !hidden(s, bold + 2))
    }

    @Test func liveDimsSyntaxInTheActiveBlock() {
        let s = styled("## Fluid mosaic\n", .live, activeLine: 0)
        #expect(!hidden(s, 0))
        #expect((s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == MarkdownStyler.dim)
    }

    @Test func sourceShowsEverythingInMonospace() {
        let s = styled("---\ndate: 2026-09-24\n---\n# Title\n", .source)
        for i in 0..<s.length { #expect(!hidden(s, i)) }
        let font = s.attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)
        #expect((s.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor) == MarkdownStyler.key)
    }

    @Test func frontmatterIsHiddenInLiveAndReading() {
        for mode in [EditorMode.live, .reading] {
            let s = styled("---\ndate: 2026-09-24\n---\n# Title\n", mode)
            #expect(hidden(s, 0) && hidden(s, 6) && hidden(s, 20))
        }
    }

    @Test func tasksBecomeCheckboxesAndDoneTasksAreStruck() {
        let s = styled("- [ ] open\n- [x] done\n", .reading)
        #expect(s.attribute(.marginCheckbox, at: 2, effectiveRange: nil) as? Bool == false)
        #expect(s.attribute(.marginCheckbox, at: 13, effectiveRange: nil) as? Bool == true)
        #expect(s.attribute(.strikethroughStyle, at: 18, effectiveRange: nil) != nil)
    }

    @Test func wikilinksCarryTheirTargetAndShowOnlyTheAlias() {
        let text = "See [[Membrane transport|transport]].\n"
        let s = styled(text, .reading)
        let open = ("See " as NSString).length
        #expect(s.attribute(.marginWikilink, at: open + 2, effectiveRange: nil) as? String == "Membrane transport")
        #expect(hidden(s, open) && hidden(s, open + 2))
        let alias = (text as NSString).range(of: "|transport").location + 1
        #expect(!hidden(s, alias))
    }
}

@MainActor @Suite struct NoteEditorModelTests {
    @Test func editsAreSavedAfterTheDebounce() async throws {
        let env = AppEnvironment.fixture()
        let m = NoteEditorModel(env: env, target: .note("bio/lecture-8"))
        await m.load()
        #expect(m.title == "Lecture 8 — Cell membrane")
        let edited = m.text + "\nOsmosis follows the gradient.\n"
        m.edit(edited)
        try await Task.sleep(for: .milliseconds(700))
        #expect(try await env.notes.open(id: "bio/lecture-8").text == edited)
        #expect(m.editedLine.hasPrefix("Edited"))
    }

    @Test func flushSavesImmediately() async throws {
        let env = AppEnvironment.fixture()
        let m = NoteEditorModel(env: env, target: .note("bio/lecture-8"))
        await m.load()
        m.edit(m.text + "x")
        await m.flush()
        #expect(try await env.notes.open(id: "bio/lecture-8").text.hasSuffix("x"))
    }

    @Test func aDraftBecomesANoteOnTheFirstSave() async throws {
        let env = AppEnvironment.fixture()
        let date = LocalDate(year: 2026, month: 10, day: 1)!
        let m = NoteEditorModel(env: env, target: .draft(course: "bio", date: date, title: "Lecture 10 — Osmosis"))
        await m.load()
        #expect(m.isDraft && m.text.hasPrefix("# Lecture 10"))
        var created: NoteSummary?
        m.onCreated = { created = $0 }
        m.edit(m.text + "Water moves to the higher solute side.\n")
        await m.flush()
        let note = try #require(created)
        #expect(!m.isDraft)
        #expect(note.title == "Lecture 10 — Osmosis")
        // The class date is written as the `date:` property.
        #expect(try await env.analysis.properties(id: note.id).first { $0.key == "date" }?.value == .date(date))
        #expect(try await env.notes.notes(course: "bio").contains { $0.id == note.id })
    }

    @Test func settingAPropertyWritesTheFrontmatter() async throws {
        let env = AppEnvironment.fixture()
        let m = NoteEditorModel(env: env, target: .note("bio/lecture-8"))
        await m.load()
        await m.setProperty("weight", .number(10))
        #expect(m.properties.contains { $0.key == "weight" })
        #expect(m.properties.first { $0.key == "weight" }?.value == .number(10))
    }

    @Test func readingTogglesBackToTheLastEditMode() {
        let m = NoteEditorModel(env: .fixture(), target: .note("bio/lecture-8"))
        m.setMode(.source)
        m.toggleReading()
        #expect(m.mode == .reading)
        m.toggleReading()
        #expect(m.mode == .source)
    }

    @Test func propertyTextParsesByType() {
        #expect(PropertyParsing.value("24.09.2026", type: .date) == .date(LocalDate(year: 2026, month: 9, day: 24)!))
        #expect(PropertyParsing.value("a, b", type: .tags) == .list([.string("a"), .string("b")]))
        #expect(PropertyParsing.value("3,5", type: .number) == .number(3.5))
        #expect(PropertyParsing.value("Cell Biology", type: .link) == .string("[[Cell Biology]]"))
    }
}
