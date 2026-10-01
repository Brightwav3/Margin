import Testing
@testable import MarginCore

/// M6-02.B: expected tokens for 59 inputs (`kind|text`, see `render`).
let tokenizerCases: [(input: String, tokens: [String])] = [
    ("# Title\n", [
        "heading.marker(1)|#",
        "heading.text(1)|Title",
    ]),
    ("### Heading with `code` and #tag ###\n", [
        "heading.marker(3)|###",
        "heading.text(3)|Heading with `code` and #tag",
        "code.inline|`code`",
        "tag|#tag",
    ]),
    ("#nospace\n", [
        "tag|#nospace",
    ]),
    ("####### seven\n", [
    ]),
    ("- item\n* item\n+ item\n", [
        "list.bullet|-",
        "list.bullet|*",
        "list.bullet|+",
    ]),
    ("1. one\n2) two\n", [
        "list.ordered|1.",
        "list.ordered|2)",
    ]),
    ("- [ ] task @Tue ^t-4f2a\n", [
        "list.bullet|-",
        "task.checkbox( )|[ ]",
        "due|@Tue",
        "block.id|^t-4f2a",
    ]),
    ("  - [x] nested @2026-10-02\n", [
        "list.bullet|-",
        "task.checkbox(x)|[x]",
        "due|@2026-10-02",
    ]),
    ("- [ ] ask @ Tue\n", [
        "list.bullet|-",
        "task.checkbox( )|[ ]",
        "due|@ Tue",
    ]),
    ("- [ ] x @before-midterm @foo\n", [
        "list.bullet|-",
        "task.checkbox( )|[ ]",
        "due|@before-midterm",
    ]),
    ("> quote\n> > nested\n", [
        "quote.marker|>",
        "quote.marker|>",
        "quote.marker|>",
    ]),
    ("> [!Note] Title\n> body\n", [
        "quote.marker|>",
        "callout(note)|[!Note]",
        "quote.marker|>",
    ]),
    ("> - [ ] task in quote\n", [
        "quote.marker|>",
        "list.bullet|-",
        "task.checkbox( )|[ ]",
    ]),
    ("```swift\nlet x = 1 // # not\n```\ntext\n", [
        "code.fence|```",
        "code.info|swift",
        "code.line|let x = 1 // # not",
        "code.fence|```",
    ]),
    ("~~~\n- [ ] no\n~~~\n", [
        "code.fence|~~~",
        "code.line|- [ ] no",
        "code.fence|~~~",
    ]),
    ("```\nunterminated\n", [
        "code.fence|```",
        "code.line|unterminated",
    ]),
    ("````\n```\n````\n", [
        "code.fence|````",
        "code.line|```",
        "code.fence|````",
    ]),
    ("``` a`b\nplain\n", [
    ]),
    ("    indented\n    more\n\n    again\n", [
        "code.indented|    indented",
        "code.indented|    more",
        "code.indented|    again",
    ]),
    ("text\n    not code\n", [
    ]),
    ("Use `code` and ``co`de``.\n", [
        "code.inline|`code`",
        "code.inline|``co`de``",
    ]),
    ("**bold** *em* ~~del~~ _u_ __b__\n", [
        "strong|**bold**",
        "emphasis|*em*",
        "strike|~~del~~",
        "emphasis|_u_",
        "strong|__b__",
    ]),
    ("***both***\n", [
        "emphasis|***both***",
        "strong|**both**",
    ]),
    ("snake_case_word and 2*3*4\n", [
        "emphasis|*3*",
    ]),
    ("**a *b* c**\n", [
        "strong|**a *b* c**",
        "emphasis|*b*",
    ]),
    ("**unclosed *x*\n", [
        "emphasis|*x*",
    ]),
    ("[[Note]] [[Note|alias]] [[Note#Head]] [[Note#Head|alias]] [[#Only]]\n", [
        "wikilink|[[Note]]",
        "wikilink.target|Note",
        "wikilink|[[Note|alias]]",
        "wikilink.target|Note",
        "wikilink.alias|alias",
        "wikilink|[[Note#Head]]",
        "wikilink.target|Note",
        "wikilink.heading|Head",
        "wikilink|[[Note#Head|alias]]",
        "wikilink.target|Note",
        "wikilink.heading|Head",
        "wikilink.alias|alias",
        "wikilink|[[#Only]]",
        "wikilink.heading|Only",
    ]),
    ("![[image.png]] ![[Note#H|A]]\n", [
        "embed.wikilink|![[image.png]]",
        "wikilink.target|image.png",
        "embed.wikilink|![[Note#H|A]]",
        "wikilink.target|Note",
        "wikilink.heading|H",
        "wikilink.alias|A",
    ]),
    ("[text](http://x.com) ![alt](img.png) [a](<b c> \"t\") [x]() [b](u(v))\n", [
        "link|[text](http://x.com)",
        "link.text|text",
        "link.destination|http://x.com",
        "embed.link|![alt](img.png)",
        "link.text|alt",
        "link.destination|img.png",
        "link|[a](<b c> \"t\")",
        "link.text|a",
        "link.destination|b c",
        "link|[x]()",
        "link.text|x",
        "link|[b](u(v))",
        "link.text|b",
        "link.destination|u(v)",
    ]),
    ("[**bold** link](x)\n", [
        "link|[**bold** link](x)",
        "link.text|**bold** link",
        "strong|**bold**",
        "link.destination|x",
    ]),
    ("#tag #a/b #123 #x-y_z C#sharp url/#frag\n", [
        "tag|#tag",
        "tag|#a/b",
        "tag|#x-y_z",
    ]),
    ("---\ntitle: x\ntags: [a]\n---\n# H\n", [
        "frontmatter.delimiter|---",
        "frontmatter|title: x",
        "frontmatter|tags: [a]",
        "frontmatter.delimiter|---",
        "heading.marker(1)|#",
        "heading.text(1)|H",
    ]),
    ("---\nnot closed\n", [
        "hr|---",
    ]),
    ("---\n---\ntext\n", [
        "frontmatter.delimiter|---",
        "frontmatter.delimiter|---",
    ]),
    ("﻿---\na: 1\n...\nbody\n", [
        "frontmatter.delimiter|---",
        "frontmatter|a: 1",
        "frontmatter.delimiter|...",
    ]),
    ("| a | b |\n|---|:-:|\n| 1 | 2 |\n| 3 | `x|y` |\n", [
        "table.header|| a | b |",
        "table.delimiter||---|:-:|",
        "table.row|| 1 | 2 |",
        "table.row|| 3 | `x|y` |",
        "code.inline|`x|y`",
    ]),
    ("a | b\n--- | ---\nc | d\n\ntext\n", [
        "table.header|a | b",
        "table.delimiter|--- | ---",
        "table.row|c | d",
    ]),
    ("| only |\ntext\n", [
    ]),
    ("|a|\n|-|\n", [
        "table.header||a|",
        "table.delimiter||-|",
    ]),
    ("---\n***\n___\n- - -\n", [
        "hr|---",
        "hr|***",
        "hr|___",
        "hr|- - -",
    ]),
    ("text ^blk-1\n", [
        "block.id|^blk-1",
    ]),
    ("para ^id then more\n", [
    ]),
    ("2^10 ^x\n", [
        "block.id|^x",
    ]),
    ("line1\r\nline2 **b**\r\n", [
        "strong|**b**",
    ]),
    ("😀 **b** 😀 [[é]]\n", [
        "strong|**b**",
        "wikilink|[[é]]",
        "wikilink.target|é",
    ]),
    ("", [
    ]),
    ("\n\n", [
    ]),
    ("\\*not em\\* \\`no\\` \\[[x]]\n", [
        "escape|\\*", "escape|\\*", "escape|\\`", "escape|\\`", "escape|\\[",
    ]),
    ("> # heading in quote\n", [
        "quote.marker|>",
        "heading.marker(1)|#",
        "heading.text(1)|heading in quote",
    ]),
    ("\t- tab list\n", [
        "code.indented|\t- tab list",
    ]),
    ("1. [ ] ordered task @today\n", [
        "list.ordered|1.",
        "task.checkbox( )|[ ]",
        "due|@today",
    ]),
    ("# Heading ^h-1\n", [
        "heading.marker(1)|#",
        "heading.text(1)|Heading ^h-1",
        "block.id|^h-1",
    ]),
    ("text #end", [
        "tag|#end",
    ]),
    ("==x== and <b>html</b>\n", [
        "highlight|==x==",
    ]),
    ("- a\n  cont\n  - b\n\n  para in list\n", [
        "list.bullet|-",
        "list.bullet|-",
    ]),
    ("text\n```\ncode\n```\n> q\n", [
        "code.fence|```",
        "code.line|code",
        "code.fence|```",
        "quote.marker|>",
    ]),
    ("* * *\n", [
        "hr|* * *",
    ]),
    ("- [ ]\n", [
        "list.bullet|-",
        "task.checkbox( )|[ ]",
    ]),
    ("-[ ] no\n", [
    ]),
]

@Suite struct MarkdownTokenizerTests {
    @Test func tokensMatchExpectationsOnAllInputs() {
        #expect(tokenizerCases.count >= 50)
        for (input, expected) in tokenizerCases {
            #expect(render(input) == expected, "input \(input.debugDescription)")
        }
    }

    @Test func offsetsAreUTF16() {
        // The emoji is one Character and two UTF-16 units (four UTF-8 bytes).
        let text = "😀 **b** [[é]]"
        let tokens = MarkdownTokenizer.tokenize(text)
        let strong = tokens.first { $0.kind == .strong }
        #expect(strong?.range == TextRange(location: 3, length: 5))
        let wiki = tokens.first { $0.kind == .wikilink(embed: false) }
        #expect(wiki?.range == TextRange(location: 9, length: 5))
        #expect(text.utf16.count == 14)
    }

    @Test func tokensAreOrderedAndProperlyNested() {
        for (input, _) in tokenizerCases {
            let tokens = MarkdownTokenizer.tokenize(input)
            let count = input.utf16.count
            var open: [TextRange] = []
            var prev = TextRange(location: 0, length: 0)
            for t in tokens {
                #expect(t.range.location >= prev.location, "order in \(input.debugDescription)")
                #expect(t.range.end <= count)
                while let top = open.last, top.end <= t.range.location { open.removeLast() }
                if let top = open.last {
                    #expect(t.range.end <= top.end, "partial overlap in \(input.debugDescription)")
                }
                open.append(t.range)
                prev = t.range
            }
        }
    }

    @Test func fenceMarkerEditRescansToMatchingFence() {
        var tk = MarkdownTokenizer(text: "a\n```\ncode\n- [ ] x\n```\nb **c**\n")
        #expect(!tk.tokens.contains { $0.kind == .taskCheckbox(checked: false) })
        // Break the opening fence: the task becomes a real task, the closing fence opens a new fence.
        let u = tk.update(edit: TextRange(location: 2, length: 1), replacement: "")
        #expect(tk.tokens == MarkdownTokenizer(text: tk.string).tokens)
        #expect(tk.tokens.contains { $0.kind == .taskCheckbox(checked: false) })
        #expect(u.retokenizedLines.count >= 3)
        // Restore it.
        tk.update(edit: TextRange(location: 2, length: 0), replacement: "`")
        #expect(tk.tokens == MarkdownTokenizer(text: tk.string).tokens)
        #expect(!tk.tokens.contains { $0.kind == .taskCheckbox(checked: false) })
    }

    @Test func typingInAParagraphOnlyTouchesNearbyLines() {
        var text = ""
        for i in 0..<200 { text += "Paragraph \(i) with **bold** and [[link]].\n" }
        var tk = MarkdownTokenizer(text: text)
        let u = tk.update(edit: TextRange(location: 5000, length: 0), replacement: "x")
        #expect(u.retokenizedLines.count <= 3)
        #expect(!u.wasFullRetokenize)
        #expect(tk.tokens == MarkdownTokenizer(text: tk.string).tokens)
    }

    @Test func frontmatterAppearingForcesFullRetokenize() {
        var tk = MarkdownTokenizer(text: "---\nkey: v\ntext\n")
        #expect(tk.tokens.first?.kind == .horizontalRule)
        let u = tk.update(edit: TextRange(location: 11, length: 0), replacement: "---\n")
        #expect(u.wasFullRetokenize)
        #expect(tk.tokens.first?.kind == .frontmatterDelimiter)
        #expect(tk.tokens == MarkdownTokenizer(text: tk.string).tokens)
    }

    @Test func tokensInRangeReturnsIntersectingLines() {
        let tk = MarkdownTokenizer(text: "# A\ntext #t\n- b\n")
        let hit = tk.tokens(in: TextRange(location: 4, length: 3))
        #expect(hit.map(\.kind) == [.tag])
        #expect(tk.lineCount == 4)
        #expect(tk.lineRange(1) == TextRange(location: 4, length: 7))
    }

    @Test func outOfRangeEditsAreClamped() {
        var tk = MarkdownTokenizer(text: "abc")
        tk.update(edit: TextRange(location: 10, length: 5), replacement: "\n# H")
        #expect(tk.string == "abc\n# H")
        #expect(tk.tokens == MarkdownTokenizer(text: "abc\n# H").tokens)
        tk.update(edit: TextRange(location: 0, length: 999), replacement: "")
        #expect(tk.string == "")
        #expect(tk.tokens.isEmpty)
    }

    @Test func crlfSplitAndJoin() {
        var tk = MarkdownTokenizer(text: "# A\r\n- [ ] t\r\n")
        tk.update(edit: TextRange(location: 4, length: 0), replacement: "x")   // between \r and \n
        #expect(tk.tokens == MarkdownTokenizer(text: tk.string).tokens)
        tk.update(edit: TextRange(location: 4, length: 1), replacement: "")
        #expect(tk.tokens == MarkdownTokenizer(text: tk.string).tokens)
        #expect(tk.lineRange(0) == TextRange(location: 0, length: 3))
    }
}
