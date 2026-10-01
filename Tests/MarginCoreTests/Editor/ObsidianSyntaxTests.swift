import Testing
@testable import MarginCore

/// Obsidian Flavored Markdown beyond CommonMark: highlights, comments, math, escapes, footnotes.
@Suite struct ObsidianSyntaxTests {
    @Test(arguments: [
        ("A ==marked== word\n", ["highlight|==marked=="]),
        ("== not == and a == b\n", []),
        ("==**bold** in it==\n", ["highlight|==**bold** in it==", "strong|**bold**"]),
        ("This is an %%inline%% comment.\n", ["comment|%%inline%%"]),
        ("50 % off\n", []),
        ("Inline $e^{2i\\pi} = 1$ math\n", ["math.inline|$e^{2i\\pi} = 1$"]),
        ("$5 and $10 dollars\n", []),
        ("\\*not italic\\*\n", ["escape|\\*", "escape|\\*"]),
        ("1\\. not a list\n", ["escape|\\."]),
        ("A footnote[^1] here.\n", ["footnote.ref|[^1]"]),
        ("[^note]: The text.\n", ["footnote.definition|[^note]:"]),
        ("Inline ^[a [[Link]] note] end\n", ["footnote.inline|^[a [[Link]] note]", "wikilink|[[Link]]", "wikilink.target|Link"]),
        ("`==code==` stays code\n", ["code.inline|`==code==`"]),
    ] as [(String, [String])])
    func inlineConstructs(input: String, tokens: [String]) {
        #expect(render(input) == tokens, "\(input)")
    }

    @Test func mathAndCommentBlocksSpanLines() {
        let text = "$$\n\\begin{vmatrix}a & b\\\\\nc & d\n\\end{vmatrix}=ad-bc\n$$\nAfter\n%%\nHidden\n%%\n"
        #expect(render(text) == [
            "math.fence|$$", "math.line|\\begin{vmatrix}a & b\\\\", "math.line|c & d", "math.line|\\end{vmatrix}=ad-bc",
            "math.fence|$$", "comment.fence|%%", "comment.line|Hidden", "comment.fence|%%",
        ])
        // Nothing inside a math block is Markdown.
        #expect(!render("$$\n**not bold** #tag\n$$\n").contains { $0.hasPrefix("strong") || $0.hasPrefix("tag") })
    }

    @Test func editingABlockFenceRetokenizesExactly() {
        var tok = MarkdownTokenizer(text: "$$\nx **y**\n$$\nafter **b**\n")
        // Breaking the opening fence turns the block back into text, and back again.
        _ = tok.update(edit: TextRange(location: 0, length: 2), replacement: "ab")
        #expect(render("ab\nx **y**\n$$\nafter **b**\n", tok.tokens) == render("ab\nx **y**\n$$\nafter **b**\n"))
        _ = tok.update(edit: TextRange(location: 0, length: 2), replacement: "$$")
        #expect(render("$$\nx **y**\n$$\nafter **b**\n", tok.tokens) == render("$$\nx **y**\n$$\nafter **b**\n"))
    }
}
