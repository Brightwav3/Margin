#if os(macOS)
import Foundation
import PDFKit
import Testing
@testable import MarginCore

/// M10-22: export to PDF draws the note on A4 pages.
@Suite struct PDFLayoutTests {
    private func pdf(_ markdown: String, title: String = "Membrány") throws -> PDFDocument {
        let data = try MacPDFRenderer().render(markdown: markdown, title: title)
        #expect(data.starts(with: Data("%PDF".utf8)))
        return try #require(PDFDocument(data: data))
    }

    @Test func drawsTheTitleAndTheText() throws {
        let doc = try pdf("# Membrány\n\n## Transport\n- osmóza **pasivní**\n- [x] přečíst kapitolu\n> [!tip] Na zkoušku\n> umět `ATP`\n\n```\nlet x = 1\n```\n")
        #expect(doc.pageCount == 1)
        let text = try #require(doc.string)
        for word in ["Membrány", "Transport", "osmóza", "pasivní", "přečíst kapitolu", "Na zkoušku", "ATP", "let x = 1"] {
            #expect(text.contains(word), "missing \(word)")
        }
        // The note's own H1 is not printed a second time under the title.
        #expect(text.components(separatedBy: "Membrány").count == 2)
        #expect(!text.contains("**") && !text.contains("`") && !text.contains("[!tip]"))
    }

    @Test func longNotesFlowOntoMorePages() throws {
        let paragraph = String(repeating: "Fosfolipidová dvojvrstva odděluje buňku od okolí. ", count: 20)
        let doc = try pdf(Array(repeating: paragraph, count: 30).joined(separator: "\n\n"))
        #expect(doc.pageCount > 3)
        #expect(doc.page(at: doc.pageCount - 1)?.string?.contains("\(doc.pageCount)") == true)
        let size = try #require(doc.page(at: 0)).bounds(for: .mediaBox).size
        #expect(abs(size.width - 595.28) < 1 && abs(size.height - 841.89) < 1)
    }

    @Test func anEmptyNoteIsOnePage() throws {
        #expect(try pdf("").pageCount == 1)
    }
}
#endif
