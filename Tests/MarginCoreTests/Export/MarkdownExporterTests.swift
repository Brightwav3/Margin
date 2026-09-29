import Foundation
import Testing
@testable import MarginCore

@Suite struct MarkdownExporterTests {
    private let notes = [
        NoteRef(id: "a", courseID: "c1", name: "Alpha", path: "Fall 2026/Course One/Alpha"),
        NoteRef(id: "b", courseID: "c1", name: "Beta", path: "Fall 2026/Course One/Beta"),
        NoteRef(id: "g1", courseID: "c1", name: "Glossary", path: "Fall 2026/Course One/Glossary"),
        NoteRef(id: "g2", courseID: "c2", name: "Glossary", path: "Fall 2026/Course Two/Glossary"),
        NoteRef(id: "u", courseID: "c2", name: "Příliš žluťoučký", path: "Fall 2026/Course Two/Příliš žluťoučký"),
        NoteRef(id: "n", courseID: "c1", name: "Nested", path: "Fall 2026/Course One/Sub Folder/Nested"),
    ]

    private func export(_ text: String, style: WikilinkExportStyle = .plainText, frontmatter: Bool = false,
                        path: String = "Fall 2026/Course One/Alpha.md", course: CourseID? = "c1") -> String {
        MarkdownExporter().export(content: text, path: path, courseID: course, notes: notes,
                                  options: ExportOptions(includeFrontmatter: frontmatter, wikilinks: style))
    }

    @Test func plainTextForms() {
        #expect(export("[[Beta]] [[Beta|b]] [[Beta#Head]] [[Beta#^blk]] [[Sub Folder/Nested]] [[#Here]] [[Beta.md]]")
                == "Beta b Beta > Head Beta Nested Here Beta")
    }

    @Test func relativeLinksFromAnyFolder() {
        #expect(export("[[Beta]] [[Nested]] [[Příliš žluťoučký]]", style: .relativeLinks)
                == "[Beta](Beta.md) [Nested](Sub%20Folder/Nested.md) [Příliš žluťoučký](../Course%20Two/P%C5%99%C3%ADli%C5%A1%20%C5%BElu%C5%A5ou%C4%8Dk%C3%BD.md)")
        #expect(export("[[Beta]]", style: .relativeLinks, path: "Fall 2026/Course One/Sub Folder/Nested.md")
                == "[Beta](../Beta.md)")
        #expect(export("[[Beta]]", style: .relativeLinks, path: "Note At Root.md") == "[Beta](Fall%202026/Course%20One/Beta.md)")
    }

    @Test func ambiguousAndMissingLinksFallBackToText() {
        // `Glossary` exists in two courses: from a third course it is ambiguous.
        #expect(export("[[Glossary]] [[Missing|alias]] [[Missing#Head]]", style: .relativeLinks, course: "c3")
                == "Glossary alias Missing > Head")
        // From course one the same-course note wins.
        #expect(export("[[Glossary]]", style: .relativeLinks) == "[Glossary](Glossary.md)")
    }

    @Test func headingAnchorsAndEscapes() {
        #expect(export("[[Beta#Cell Cycle: G1/S (phase)]]", style: .relativeLinks) == "[Beta](Beta.md#cell-cycle-g1s-phase)")
        // Not a wikilink for the scanner (nested brackets): left alone.
        #expect(export("[[Beta|a [b] c]]", style: .relativeLinks) == "[[Beta|a [b] c]]")
    }

    @Test func imagesAndEmbeds() {
        #expect(export("![[my pic.PNG]] ![[pic.png|200]] ![[Beta]]") == "![my pic.PNG](_files/my%20pic.PNG) ![pic.png](_files/pic.png) Beta")
        #expect(export("![[Beta]]", style: .relativeLinks) == "[Beta](Beta.md)")
    }

    @Test func codeAndOtherMarkdownAreUntouched() {
        let text = "`[[a]]`\n\n```swift\n[[Beta]]\n```\n\n[[Beta]] [x](y.md) ![i](p.png) - [x] done ^t-1\r\nnext\r\n"
        #expect(export(text) == "`[[a]]`\n\n```swift\n[[Beta]]\n```\n\nBeta [x](y.md) ![i](p.png) - [x] done ^t-1\r\nnext\r\n")
    }

    @Test func frontmatterIsDroppedOrKeptVerbatim() {
        let file = "---\r\nid: a\r\n# comment\r\nclass: \"[[Course One]]\"\r\n---\r\n# Alpha\r\nSee [[Beta]]\r\n"
        #expect(export(file) == "# Alpha\r\nSee Beta\r\n")
        // The block is not touched, even where it holds a link.
        #expect(export(file, frontmatter: true) == "---\r\nid: a\r\n# comment\r\nclass: \"[[Course One]]\"\r\n---\r\n# Alpha\r\nSee Beta\r\n")
        #expect(export("no frontmatter, [[Beta]]") == "no frontmatter, Beta")
        #expect(export("") == "")
    }

    @Test func multibyteTextAroundLinksSurvives() {
        #expect(export("Žluťoučký 🎓 [[Beta]] — konec 🎓 [[Alpha|é]]\n") == "Žluťoučký 🎓 Beta — konec 🎓 é\n")
    }

    @Test func pdfNeedsARenderer() throws {
        struct Fake: PDFRenderer {
            func render(markdown: String, title: String) throws -> Data { Data("PDF:\(title):\(markdown)".utf8) }
        }
        let none = ExportEngine(pdf: nil)
        #expect(throws: MarginError.invalid("PDF export requires macOS")) {
            try none.export(title: "T", path: "T.md", content: "x", courseID: nil, notes: [], format: .pdf, options: ExportOptions())
        }
        let file = try ExportEngine(pdf: Fake()).export(title: "My: Title?", path: "T.md", content: "---\na: 1\n---\nhi [[X]]", courseID: nil,
                                                       notes: [], format: .pdf, options: ExportOptions())
        #expect(file.format == .pdf && file.fileName == VaultPath.filename(fromTitle: "My: Title?") + ".pdf")
        #expect(String(data: file.data, encoding: .utf8) == "PDF:My: Title?:hi X" && file.text == nil)
    }
}
