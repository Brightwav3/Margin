import AppKit
import MarginCore
import Testing
@testable import MarginUI

/// D-027: math and Mermaid blocks render offline into pictures.
@MainActor @Suite(.serialized) struct BlockRendererTests {
    @Test func rendersMath() async throws {
        let r = try #require(await BlockRenderer.shared.render(.math, #"\int_0^1 x^2\,dx = \frac{1}{3}"#))
        #expect(!r.isError)
        #expect(r.image.size.width > 60 && r.image.size.height > 20)
    }

    @Test func rendersAMermaidDiagram() async throws {
        let r = try #require(await BlockRenderer.shared.render(.mermaid, "graph TD\n  A[Membrána] --> B[Transport]\n  B --> C[Osmóza]"))
        #expect(!r.isError)
        #expect(r.image.size.height > 100)
    }

    @Test func aBrokenBlockGivesAnErrorPicture() async throws {
        let r = try #require(await BlockRenderer.shared.render(.math, #"\frac{1}{"#))
        #expect(r.isError)
    }
}

/// The editor shows rendered blocks outside the block being edited, and the source inside it.
@MainActor @Suite(.serialized) struct RenderedBlockStylingTests {
    private func styled(_ text: String, activeLine: Int? = nil) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let tokenizer = MarkdownTokenizer(text: text)
        MarkdownStyler.apply(to: storage, range: NSRange(location: 0, length: storage.length), tokens: tokenizer.tokens,
                             mode: .live, active: activeLine.flatMap { tokenizer.lineRange($0) })
        return storage
    }

    @Test func mathAndMermaidBlocksBecomePictures() async throws {
        let text = "Úvod\n\n$$\nE = mc^2\n$$\n\n```mermaid\ngraph TD\n  A --> B\n```\n\nKonec\n"
        _ = await BlockRenderer.shared.render(.math, "E = mc^2")
        _ = await BlockRenderer.shared.render(.mermaid, "graph TD\n  A --> B")
        let s = styled(text)
        let ns = text as NSString
        #expect(s.attribute(.marginRendered, at: ns.range(of: "$$").location, effectiveRange: nil) as? String == BlockRenderer.key(.math, "E = mc^2"))
        #expect(s.attribute(.marginRendered, at: ns.range(of: "```mermaid").location, effectiveRange: nil) as? String
                == BlockRenderer.key(.mermaid, "graph TD\n  A --> B"))
        #expect(s.attribute(.marginHidden, at: ns.range(of: "mc^2").location, effectiveRange: nil) != nil)
        #expect(s.attribute(.marginHidden, at: ns.range(of: "Konec").location, effectiveRange: nil) == nil)
        // Editing the formula shows its source again.
        let editing = styled(text, activeLine: 3)
        #expect(editing.attribute(.marginRendered, at: ns.range(of: "$$").location, effectiveRange: nil) == nil)
    }

    @Test func otherCodeBlocksStayCode() {
        let s = styled("```swift\nlet x = 1\n```\n")
        #expect(s.attribute(.marginRendered, at: 0, effectiveRange: nil) == nil)
    }
}
