import Testing
@testable import MarginCore

@Suite struct CaptureRulesTests {
    @Test func appendLineAddsTheMissingBreak() {
        #expect(CaptureRules.append(line: "x", to: "a") == "a\nx\n")
        #expect(CaptureRules.append(line: "x", to: "a\n") == "a\nx\n")
        #expect(CaptureRules.append(line: "x", to: "") == "x\n")
    }

    @Test func appendLineKeepsCRLF() {
        #expect(CaptureRules.append(line: "x", to: "a\r\nb") == "a\r\nb\r\nx\r\n")
        #expect(CaptureRules.append(line: "x", to: "a\r\nb\r\n") == "a\r\nb\r\nx\r\n")
    }

    @Test func appendParagraphNeedsOneBlankLine() {
        #expect(CaptureRules.append(paragraph: "p", to: "a") == "a\n\np\n")
        #expect(CaptureRules.append(paragraph: "p", to: "a\n") == "a\n\np\n")
        #expect(CaptureRules.append(paragraph: "p", to: "a\n\n") == "a\n\np\n")
        #expect(CaptureRules.append(paragraph: "p", to: "a\r\n") == "a\r\n\r\np\r\n")
        #expect(CaptureRules.append(paragraph: "p", to: "a\r\n\r\n") == "a\r\n\r\np\r\n")
        #expect(CaptureRules.append(paragraph: "p", to: "") == "p\n")
    }

    @Test func taskLineHasTagsDueAndIDInOrder() {
        let due = LocalDate(year: 2026, month: 10, day: 2)
        #expect(CaptureRules.taskLine(text: "Read\nchapter 7", tags: ["#a b", "A-B", ""], due: due, id: "t-4f2a")
                == "- [ ] Read chapter 7 #a-b @2026-10-02 ^t-4f2a")
        #expect(CaptureRules.taskLine(text: "x", tags: [], due: nil, id: "t-1") == "- [ ] x ^t-1")
    }

    @Test func titleIsTheFirstLineCutAtAWord() {
        #expect(CaptureRules.title(from: "Short\nsecond") == "Short")
        let long = String(repeating: "word ", count: 30)
        let t = CaptureRules.title(from: long)
        #expect(t.count <= CaptureRules.titleLimit)
        #expect(t.hasSuffix("word"))
        #expect(CaptureRules.title(from: String(repeating: "x", count: 100)).count == CaptureRules.titleLimit)
    }

    @Test func inboxFileRoundTrips() throws {
        let item = InboxItem(id: "i", text: "Email Dr. Okafor", kind: .task, source: .phone,
                             captured: LocalDateTime(date: .literal(2026, 9, 28), time: .literal(9, 12)))
        let parsed = try #require(CaptureRules.parseInboxFile(stem: "i", content: CaptureRules.inboxFile(item), fallback: item.captured))
        #expect(parsed == item)
        #expect(CaptureRules.inboxStem(captured: item.captured, text: item.text) == "2026-09-28 0912 Email Dr. Okafor")
        #expect(CaptureRules.parseInboxFile(stem: "x", content: "---\nkind: task\n---\n \n", fallback: item.captured) == nil)
    }
}
