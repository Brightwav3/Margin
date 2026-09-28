import Testing
@testable import MarginCore

@Suite struct MarkdownScannerTests {
    let scanner = MarkdownScanner()

    @Test func taskInsideFencedCodeIsNotATask() {
        let text = "- [ ] real\n```\n- [ ] fake\n```\n- [x] also real\n"
        let scan = scanner.scan(text)
        #expect(scan.tasks.map(\.rawText) == ["real", "also real"])
        #expect(scan.tasks.map(\.line) == [1, 5])
        #expect(scan.codeBlocks.count == 1)
        #expect(scan.codeBlocks[0].lines == 2...4)
    }

    @Test func listAfterFenceEndsTheListSoIndentedCodeIsNotATask() {
        let text = "- [ ] a\n\n```\ncode\n```\n\n    - [ ] code, not a task\n\n- [ ] b\n"
        let scan = scanner.scan(text)
        #expect(scan.tasks.map(\.rawText) == ["a", "b"])
    }

    @Test func taskOnFirstLineAfterByteOrderMark() {
        let scan = scanner.scan("\u{FEFF}- [ ] first\n- [x] second\n")
        #expect(scan.tasks.map(\.rawText) == ["first", "second"])
        #expect(scan.tasks.map(\.line) == [1, 2])
        #expect(scan.tasks[0].range == ByteRange(start: 3, end: 3 + "- [ ] first".utf8.count))
        let heading = scanner.scan("\u{FEFF}# Title\n")
        #expect(heading.headings.map(\.text) == ["Title"])
        #expect(scanner.scan("\u{FEFF}").lineCount <= 1)
    }

    @Test func tildeFenceAndInfoString() {
        let scan = scanner.scan("~~~python title\n- [ ] no\n~~~\n")
        #expect(scan.tasks.isEmpty)
        #expect(scan.codeBlocks[0].info == "python title")
        #expect(scan.codeBlocks[0].isTerminated)
    }

    @Test func unterminatedFenceRunsToEOF() {
        let scan = scanner.scan("intro\n```swift\n# not heading\n- [ ] no\n[[x]]")
        #expect(scan.headings.isEmpty && scan.tasks.isEmpty && scan.links.isEmpty)
        #expect(scan.codeBlocks[0].lines == 2...5)
        #expect(!scan.codeBlocks[0].isTerminated)
        #expect(scan.codeBlocks[0].info == "swift")
    }

    @Test func shorterOrMismatchedFenceDoesNotClose() {
        let scan = scanner.scan("````\n```\n~~~~\n- [ ] no\n````\n- [ ] yes")
        #expect(scan.codeBlocks.count == 1)
        #expect(scan.codeBlocks[0].lines == 1...5)
        #expect(scan.tasks.map(\.rawText) == ["yes"])
    }

    @Test func backtickFenceInfoCannotContainBacktick() {
        let scan = scanner.scan("``` a`b\n- [ ] task\n")
        #expect(scan.codeBlocks.isEmpty)
        #expect(scan.tasks.count == 1)
    }

    @Test func indentedCodeNeedsBlankLineAndIsIgnored() {
        let scan = scanner.scan("Para\n\n    - [ ] code\n    # code\n\n- [ ] task\n")
        #expect(scan.codeBlocks.count == 1)
        #expect(scan.codeBlocks[0].kind == .indented)
        #expect(scan.codeBlocks[0].lines == 3...4)
        #expect(scan.tasks.map(\.line) == [6])
        #expect(scan.headings.isEmpty)
    }

    @Test func nestedTaskUnderListIsNotIndentedCode() {
        let scan = scanner.scan("- [ ] parent\n\n    - [ ] child\n")
        #expect(scan.codeBlocks.isEmpty)
        #expect(scan.tasks.count == 2)
        #expect(scan.tasks[1].indent == 4)
    }

    @Test func headingsWithLevelsAndClosingHashes() {
        let scan = scanner.scan("# One\n## Two ##\n###### Six\n####### seven\n#NoSpace\n    # indented\n#\n")
        #expect(scan.headings.map(\.level) == [1, 2, 6, 1])
        #expect(scan.headings.map(\.text) == ["One", "Two", "Six", ""])
        #expect(scan.headings.map(\.line) == [1, 2, 3, 7])
    }

    @Test func frontmatterIsSkipped() {
        let text = "---\ntitle: x\ntags: [a, b]\n# comment\n- [ ] yaml\n---\n# Real\n- [ ] task [[Link]]\n"
        let scan = scanner.scan(text)
        #expect(scan.frontmatterLines == 1...6)
        #expect(scan.headings.map(\.text) == ["Real"])
        #expect(scan.tasks.map(\.line) == [8])
        #expect(scan.links.count == 1)
    }

    @Test func unclosedFrontmatterIsNotFrontmatter() {
        let scan = scanner.scan("---\n# Heading\n- [ ] task\n")
        #expect(scan.frontmatterLines == nil)
        #expect(scan.headings.count == 1)
        #expect(scan.tasks.count == 1)
    }

    @Test func taskMarkersAndStates() {
        let scan = scanner.scan("- [ ] a\n- [x] b\n* [ ] c\n+ [X] d\n- [] no\n- [y] no\n-[ ] no\n- [ ]\n1. [ ] no\n")
        #expect(scan.tasks.map(\.rawText) == ["a", "b", "c", "d"])
        #expect(scan.tasks.map(\.done) == [false, true, false, true])
        #expect(scan.tasks.map(\.marker) == ["-", "-", "*", "+"])
    }

    @Test func linksOutsideCodeOnly() {
        let text = "A [[One]] and `[[Two]]` and ``[[Three]] ` x`` and ![[Img.png]] [t](http://x.y/(z)) \\[[Esc]]\n"
        let scan = scanner.scan(text)
        #expect(scan.links.map(\.inner) == ["One", "Img.png", "http://x.y/(z)"])
        #expect(scan.links.map(\.isEmbed) == [false, true, false])
        #expect(scan.links[2].label == "t")
        #expect(scan.links[2].kind == .markdown)
    }

    @Test func rangesAreUTF8ByteOffsets() {
        let text = "Čau [[Á]]\n- [ ] ř\n"
        let scan = scanner.scan(text)
        let link = scan.links[0]
        let bytes = Array(text.utf8)
        #expect(String(decoding: bytes[link.range.start..<link.range.end], as: UTF8.self) == "[[Á]]")
        #expect(scan.tasks[0].range.start == 12)
        #expect(String(decoding: bytes[scan.tasks[0].range.start..<scan.tasks[0].range.end], as: UTF8.self) == "- [ ] ř")
    }

    @Test func crlfAndNoTrailingNewline() {
        let scan = scanner.scan("# T\r\n- [ ] a\r\n```\r\n- [ ] b\r\n```\r\n- [ ] c")
        #expect(scan.tasks.map(\.rawText) == ["a", "c"])
        #expect(scan.tasks.map(\.line) == [2, 6])
        #expect(scan.lineCount == 6)
    }

    @Test func emptyAndDegenerateInputs() {
        #expect(scanner.scan("").lineCount == 0)
        #expect(scanner.scan("\n\n").tasks.isEmpty)
        _ = scanner.scan("[[")
        _ = scanner.scan("[[]]")
        _ = scanner.scan("[](")
        _ = scanner.scan("```")
        #expect(scanner.scan("[[ ]]").links.isEmpty)
    }

    @Test func listContextEndsAtParagraph() {
        let scan = scanner.scan("- item\n\nParagraph\n\n    code [[x]]\n")
        #expect(scan.codeBlocks.count == 1)
        #expect(scan.links.isEmpty)
    }
}
