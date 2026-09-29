import Foundation
import Testing
@testable import MarginCore

@Suite struct SearchSnippetTests {
    private func texts(_ s: String, _ ranges: [HighlightRange]) -> [String] {
        let chars = Array(s)
        return ranges.map { String(chars[$0.location..<($0.location + $0.length)]) }
    }

    @Test func passageAroundTheMatchWithEllipses() throws {
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 30)
        let body = "# Title\n\n" + filler + "The Mitóza phase.\n\n" + filler
        let p = try #require(SearchSnippet.passage(of: body, query: FullTextQuery("mitoza")))
        #expect(p.text.hasPrefix("…") && p.text.hasSuffix("…"))
        #expect(p.text.contains("Mitóza"))
        #expect(!p.text.contains("\n"))
        #expect(p.text.count <= SearchSnippet.width + 2)
        #expect(texts(p.text, p.highlights) == ["Mitóza"])
        // No partial words at the cut.
        let words = p.text.dropFirst().dropLast().split(separator: " ")
        #expect(words.allSatisfy { ["lorem", "ipsum", "dolor", "sit", "amet", "The", "Mitóza", "phase."].contains(String($0)) })
    }

    @Test func matchAtTheStartHasNoLeadingEllipsis() throws {
        let p = try #require(SearchSnippet.passage(of: "Enzymes speed up reactions.", query: FullTextQuery("enz")))
        #expect(p.text == "Enzymes speed up reactions.")
        #expect(texts(p.text, p.highlights) == ["Enzymes"])
    }

    @Test func prefersTheWindowWithMostQueryWords() throws {
        let filler = String(repeating: "filler words here ", count: 20)
        let body = "alpha " + filler + "beta " + filler + "alpha beta together"
        let p = try #require(SearchSnippet.passage(of: body, query: FullTextQuery("alpha beta")))
        #expect(p.text.contains("alpha beta together"))
        #expect(Set(texts(p.text, p.highlights).map { $0.lowercased() }) == ["alpha", "beta"])
    }

    @Test func noMatchGivesNil() {
        #expect(SearchSnippet.passage(of: "nothing here", query: FullTextQuery("zzz")) == nil)
        #expect(SearchSnippet.passage(of: "text", query: FullTextQuery("")) == nil)
        #expect(SearchSnippet.highlights(in: "text", query: FullTextQuery("")).isEmpty)
    }

    @Test func lastWordIsAPrefixOnlyWhileTyping() {
        #expect(SearchSnippet.highlights(in: "membrane", query: FullTextQuery("membr")).count == 1)
        #expect(SearchSnippet.highlights(in: "membrane", query: FullTextQuery("membr ")).isEmpty)
    }
}
