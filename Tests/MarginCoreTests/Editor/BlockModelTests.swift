import Testing
@testable import MarginCore

/// M6-12.B: expected blocks for 44 documents (`kind L<first>-<last> text`, see `renderBlocks`).
let blockCases: [(input: String, blocks: [String])] = [
    ("", [
        "blank L0-0 ",
    ]),
    ("\n", [
        "blank L0-1 ⏎",
    ]),
    ("Hello world\n", [
        "paragraph L0-0 Hello world",
        "blank L1-1 ",
    ]),
    ("Line one\nline two\n\nSecond para\n", [
        "paragraph L0-1 Line one⏎line two",
        "blank L2-2 ",
        "paragraph L3-3 Second para",
        "blank L4-4 ",
    ]),
    ("# Title\ntext right after\n", [
        "heading(1) L0-0 # Title",
        "paragraph L1-1 text right after",
        "blank L2-2 ",
    ]),
    ("# A\n## B\n### C", [
        "heading(1) L0-0 # A",
        "heading(2) L1-1 ## B",
        "heading(3) L2-2 ### C",
    ]),
    ("- a\n- b\n- c\n", [
        "item L0-0 - a",
        "item L1-1 - b",
        "item L2-2 - c",
        "blank L3-3 ",
    ]),
    ("1. one\n2. two\n", [
        "item(ordered) L0-0 1. one",
        "item(ordered) L1-1 2. two",
        "blank L2-2 ",
    ]),
    ("- [ ] t1\n- [x] t2\n", [
        "task( ) L0-0 - [ ] t1",
        "task(x) L1-1 - [x] t2",
        "blank L2-2 ",
    ]),
    ("- item\n  continuation\n  more\n- next\n", [
        "item L0-2 - item⏎  continuation⏎  more",
        "item L3-3 - next",
        "blank L4-4 ",
    ]),
    ("- item\n\n  para in item\n", [
        "item L0-0 - item",
        "blank L1-1 ",
        "paragraph L2-2   para in item",
        "blank L3-3 ",
    ]),
    ("- a\n  - b\n    - c\n", [
        "item L0-0 - a",
        "item L1-1   - b",
        "item L2-2     - c",
        "blank L3-3 ",
    ]),
    ("```swift\nlet x = 1\n\nlet y = 2\n```\n", [
        "fence(swift,closed) L0-4 ```swift⏎let x = 1⏎⏎let y = 2⏎```",
        "blank L5-5 ",
    ]),
    ("```\nunterminated\n\ncode", [
        "fence(-,open) L0-3 ```⏎unterminated⏎⏎code",
    ]),
    ("text\n```\ncode\n```\nafter\n", [
        "paragraph L0-0 text",
        "fence(-,closed) L1-3 ```⏎code⏎```",
        "paragraph L4-4 after",
        "blank L5-5 ",
    ]),
    ("~~~\n# not heading\n~~~\n", [
        "fence(-,closed) L0-2 ~~~⏎# not heading⏎~~~",
        "blank L3-3 ",
    ]),
    ("````\n```\ninner\n```\n````\n", [
        "fence(-,closed) L0-4 ````⏎```⏎inner⏎```⏎````",
        "blank L5-5 ",
    ]),
    ("    indented\n\n    again\n\nafter\n", [
        "indented L0-2     indented⏎⏎    again",
        "blank L3-3 ",
        "paragraph L4-4 after",
        "blank L5-5 ",
    ]),
    ("| a | b |\n|---|---|\n| 1 | 2 |\n", [
        "table L0-2 | a | b |⏎|---|---|⏎| 1 | 2 |",
        "blank L3-3 ",
    ]),
    ("para\n| a | b |\n|---|---|\n| 1 | 2 |\n\nafter\n", [
        "paragraph L0-0 para",
        "table L1-3 | a | b |⏎|---|---|⏎| 1 | 2 |",
        "blank L4-4 ",
        "paragraph L5-5 after",
        "blank L6-6 ",
    ]),
    ("| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ntext line\n", [
        "table L0-3 | a | b |⏎|---|---|⏎| 1 | 2 |⏎| 3 | 4 |",
        "paragraph L4-4 text line",
        "blank L5-5 ",
    ]),
    ("a | b\n--- | ---\nc | d\n\nx | y\n--- | ---\nz | w\n", [
        "table L0-2 a | b⏎--- | ---⏎c | d",
        "blank L3-3 ",
        "table L4-6 x | y⏎--- | ---⏎z | w",
        "blank L7-7 ",
    ]),
    ("| only header |\nnot table\n", [
        "paragraph L0-1 | only header |⏎not table",
        "blank L2-2 ",
    ]),
    ("> quote one\n> quote two\n\n> another\n", [
        "quote L0-1 > quote one⏎> quote two",
        "blank L2-2 ",
        "quote L3-3 > another",
        "blank L4-4 ",
    ]),
    ("> [!note] Title\n> body\n> more\n", [
        "callout(note) L0-2 > [!note] Title⏎> body⏎> more",
        "blank L3-3 ",
    ]),
    ("> [!tip]\n> a\n\n> [!warning]\n> b\n> [!danger]\n> c\n", [
        "callout(tip) L0-1 > [!tip]⏎> a",
        "blank L2-2 ",
        "callout(warning) L3-4 > [!warning]⏎> b",
        "callout(danger) L5-6 > [!danger]⏎> c",
        "blank L7-7 ",
    ]),
    ("> plain\n> [!info]\n> x\n", [
        "quote L0-0 > plain",
        "callout(info) L1-2 > [!info]⏎> x",
        "blank L3-3 ",
    ]),
    ("---\ntitle: T\ntags: [a]\n---\n# H\n", [
        "frontmatter L0-3 ---⏎title: T⏎tags: [a]⏎---",
        "heading(1) L4-4 # H",
        "blank L5-5 ",
    ]),
    ("---\nunclosed\ntext\n", [
        "hr L0-0 ---",
        "paragraph L1-2 unclosed⏎text",
        "blank L3-3 ",
    ]),
    ("---\n---\nbody\n", [
        "frontmatter L0-1 ---⏎---",
        "paragraph L2-2 body",
        "blank L3-3 ",
    ]),
    ("text\n---\ntext\n***\n___\n", [
        "paragraph L0-0 text",
        "hr L1-1 ---",
        "paragraph L2-2 text",
        "hr L3-3 ***",
        "hr L4-4 ___",
        "blank L5-5 ",
    ]),
    ("\n\n# H\n\n\n\ntext\n", [
        "blank L0-1 ⏎",
        "heading(1) L2-2 # H",
        "blank L3-5 ⏎⏎",
        "paragraph L6-6 text",
        "blank L7-7 ",
    ]),
    ("# H\n\n- [ ] a\n\n```js\nx\n```\n\n| a |\n|---|\n| 1 |\n\n> q\n\n---\n", [
        "heading(1) L0-0 # H",
        "blank L1-1 ",
        "task( ) L2-2 - [ ] a",
        "blank L3-3 ",
        "fence(js,closed) L4-6 ```js⏎x⏎```",
        "blank L7-7 ",
        "table L8-10 | a |⏎|---|⏎| 1 |",
        "blank L11-11 ",
        "quote L12-12 > q",
        "blank L13-13 ",
        "hr L14-14 ---",
        "blank L15-15 ",
    ]),
    ("para\n\n\n\npara2", [
        "paragraph L0-0 para",
        "blank L1-3 ⏎⏎",
        "paragraph L4-4 para2",
    ]),
    ("- a\ntext lazy\n", [
        "item L0-0 - a",
        "paragraph L1-1 text lazy",
        "blank L2-2 ",
    ]),
    ("Text with **bold** and `code`\nsecond line\n", [
        "paragraph L0-1 Text with **bold** and `code`⏎second line",
        "blank L2-2 ",
    ]),
    ("1. a\n   cont\n2. b\n\ntext\n", [
        "item(ordered) L0-1 1. a⏎   cont",
        "item(ordered) L2-2 2. b",
        "blank L3-3 ",
        "paragraph L4-4 text",
        "blank L5-5 ",
    ]),
    ("```\n---\n# no\n> no\n- [ ] no\n```\n", [
        "fence(-,closed) L0-5 ```⏎---⏎# no⏎> no⏎- [ ] no⏎```",
        "blank L6-6 ",
    ]),
    ("﻿---\na: 1\n---\nx\n", [
        "frontmatter L0-2 ﻿---⏎a: 1⏎---",
        "paragraph L3-3 x",
        "blank L4-4 ",
    ]),
    ("line1\r\nline2\r\n\r\n# H\r\n- a\r\n", [
        "paragraph L0-1 line1\r\nline2",
        "blank L2-2 ",
        "heading(1) L3-3 # H",
        "item L4-4 - a",
        "blank L5-5 ",
    ]),
    ("* a\n* b\n\n\n* c\n", [
        "item L0-0 * a",
        "item L1-1 * b",
        "blank L2-3 ⏎",
        "item L4-4 * c",
        "blank L5-5 ",
    ]),
    ("> - [ ] task in quote\n> > nested\n", [
        "quote L0-1 > - [ ] task in quote⏎> > nested",
        "blank L2-2 ",
    ]),
    ("    code after list\n- a\n\n    still item\n", [
        "indented L0-0     code after list",
        "item L1-1 - a",
        "blank L2-2 ",
        "paragraph L3-3     still item",
        "blank L4-4 ",
    ]),
    ("a\n\n    code\n    code2\nback\n", [
        "paragraph L0-0 a",
        "blank L1-1 ",
        "indented L2-3     code⏎    code2",
        "paragraph L4-4 back",
        "blank L5-5 ",
    ]),
]

@Suite struct BlockModelTests {
    @Test func blocksMatchExpectationsOnAllDocuments() {
        #expect(blockCases.count >= 40)
        for (input, expected) in blockCases {
            #expect(renderBlocks(input) == expected, "document \(input.debugDescription)")
        }
    }

    @Test func blocksTileAllLinesAndStayInsideTheDocument() {
        for (input, _) in blockCases {
            let tk = MarkdownTokenizer(text: input)
            let model = tk.blockModel()
            var nextLine = 0
            for b in model.blocks {
                #expect(b.lineRange.lowerBound == nextLine, "gap in \(input.debugDescription)")
                #expect(!b.lineRange.isEmpty)
                nextLine = b.lineRange.upperBound
                #expect(b.range.end <= tk.utf16Count)
                #expect(b.range.location == tk.lineRange(b.lineRange.lowerBound)?.location)
                #expect(b.range.end == tk.lineRange(b.lineRange.upperBound - 1)?.end)
            }
            #expect(nextLine == tk.lineCount)
        }
    }

    @Test func activeBlockFollowsTheCursor() {
        let text = "# Title\n\ntext one\ntext two\n\n```\ncode\n```\n"
        let model = BlockModel(text: text)
        // Offsets: "# Title"=0..7, blank line=8, "text one"=9..17, "text two"=18..26, blank=27,
        // fence=28..
        #expect(model.activeBlock(at: 0).kind == .heading(level: 1))
        #expect(model.activeBlock(at: 7).kind == .heading(level: 1))     // end of the heading line
        #expect(model.activeBlock(at: 8).kind == .blank)                 // on the empty line
        #expect(model.activeBlock(at: 9).kind == .paragraph)
        #expect(model.activeBlock(at: 26).kind == .paragraph)           // end of the last paragraph line
        #expect(model.activeBlock(at: 27).kind == .blank)
        #expect(model.activeBlock(at: 30).kind == .codeFence(info: nil, terminated: true))
        #expect(model.activeBlock(at: 41).kind == .blank)                // after the final newline
        // Out-of-range cursors are clamped.
        #expect(model.activeBlock(at: -5).kind == .heading(level: 1))
        #expect(model.activeBlock(at: 10_000).kind == .blank)
    }

    @Test func activeBlockInsideACodeFenceWithBlankLinesAndTables() {
        let text = "```\na\n\nb\n```\n| h |\n|---|\n| c |\n"
        let model = BlockModel(text: text)
        #expect(model.blocks.count == 3)
        let blank = NSStringLike(text: text).offset(of: "a\n\n") + 2   // the empty line
        // The empty line inside the fence still belongs to the fence.
        #expect(model.activeBlock(at: blank).kind == .codeFence(info: nil, terminated: true))
        let tableOffset = NSStringLike(text: text).offset(of: "| c |")
        #expect(model.activeBlock(at: tableOffset).kind == .table)
    }

    @Test func crlfCursorBetweenCarriageReturnAndLineFeedBelongsToTheLine() {
        let text = "one\r\n\r\ntwo\r\n"
        let model = BlockModel(text: text)
        #expect(model.blocks.count == 4)
        #expect(model.activeBlock(at: 3).lineRange == 0..<1)   // before \r
        #expect(model.activeBlock(at: 4).lineRange == 0..<1)   // between \r and \n
        #expect(model.activeBlock(at: 5).lineRange == 1..<2)   // the blank line
    }

    @Test func blocksIntersectingARange() {
        let model = BlockModel(text: "# A\n\ntext\n\n- b\n")
        let hit = model.blocks(intersecting: TextRange(location: 4, length: 8))
        #expect(hit.map(\.kind) == [.blank, .paragraph, .blank, .listItem(ordered: false)])
        #expect(model.blocks(intersecting: TextRange(location: 0, length: 0)).map(\.kind) == [.heading(level: 1)])
    }

    @Test func incrementalUpdatesKeepTheBlockModelInSync() {
        var tk = MarkdownTokenizer(text: "text\n\n```\ncode\n```\n")
        tk.update(edit: TextRange(location: 6, length: 3), replacement: "")   // remove the opening fence
        #expect(tk.blockModel() == BlockModel(text: tk.string))
        #expect(tk.blockModel().blocks.contains { $0.kind == .codeFence(info: nil, terminated: false) })
    }
}

/// Minimal helper to find a substring's UTF-16 offset without Foundation.
struct NSStringLike {
    let text: String
    func offset(of needle: String) -> Int {
        let h = Array(text.utf16), n = Array(needle.utf16)
        for i in 0...(h.count - n.count) where Array(h[i..<(i + n.count)]) == n { return i }
        return -1
    }
}
