import Foundation
import Testing
@testable import MarginCore

@Suite struct IDAssignerTests {
    // MARK: Basics

    @Test func addsNoteIDAndTaskIDsToANoteWithoutFrontmatter() {
        let r = assign("# Title\n\n- [ ] one\n- [x] two @2026-10-01\n\ntext\n")
        #expect(masked(r.text) == "---\nid: N\n---\n# Title\n\n- [ ] one ^T\n- [x] two @2026-10-01 ^T\n\ntext\n")
        #expect(r.noteOutcome == .added)
        #expect(r.tasks.map(\.outcome) == [.added, .added])
        #expect(r.tasks.map(\.line) == [3, 4])
        #expect(r.didChange)
        #expect(r.noteID.map { StableIDGenerator.isGenerated($0, kind: .note) } == true)
    }

    @Test func appendsIDToExistingFrontmatterWithoutTouchingOtherEntries() {
        let text = "---\ntype: lecture # keep\ndate: 2026-09-24\ntags: [a, b]\nclass: \"[[Bio]]\"\n---\n# T\n- [ ] x\n"
        let r = assign(text)
        #expect(masked(r.text) == "---\ntype: lecture # keep\ndate: 2026-09-24\ntags: [a, b]\nclass: \"[[Bio]]\"\nid: N\n---\n# T\n- [ ] x ^T\n")
    }

    @Test func existingNoteIDIsNeverChanged() {
        let text = "---\nid: n-9c1e\ntype: note\n---\nbody\n- [ ] a ^t-aaaa\n"
        let r = assign(text)
        #expect(r.text == text)
        #expect(r.noteOutcome == .kept)
        #expect(r.noteID == "n-9c1e")
        #expect(!r.didChange)
    }

    @Test func aNonGeneratedNoteIDIsAlsoKept() {
        for id in ["my-note", "42", "\"quoted id\"", "N-UPPER"] {
            let text = "---\nid: \(id)\n---\nbody\n"
            let r = assign(text)
            #expect(r.text == text, "id \(id)")
            #expect(r.noteOutcome == .kept)
        }
    }

    @Test func emptyIDEntryIsFilledInPlace() {
        let r = assign("---\ntype: note\nid:\ntags: [x]\n---\nbody\n")
        #expect(masked(r.text) == "---\ntype: note\nid: N\ntags: [x]\n---\nbody\n")
        #expect(r.noteOutcome == .added)
    }

    @Test func tasksThatAlreadyHaveIDsAreLeftAlone() {
        let text = "---\nid: n-9c1e\n---\n- [ ] a ^t-aaaa\n- [x] b @Tue ^t-bbbb\n  - [ ] c ^t-cccc\n"
        let r = assign(text)
        #expect(r.text == text)
        #expect(r.tasks.map(\.id) == ["t-aaaa", "t-bbbb", "t-cccc"])
        #expect(r.tasks.allSatisfy { $0.outcome == .kept })
    }

    @Test func aForeignBlockIDBecomesTheTaskIDWithoutAddingASecondOne() {
        let text = "---\nid: n-1111\n---\n- [ ] see below ^my-block\n- [ ] plain\n"
        let r = assign(text)
        #expect(masked(r.text) == "---\nid: N\n---\n- [ ] see below ^my-block\n- [ ] plain ^T\n")
        #expect(r.tasks[0].id == "my-block")
        #expect(r.tasks[0].outcome == .kept)
        #expect(!r.text.contains("^my-block ^t-"))
    }

    @Test func isIdempotent() {
        let text = "\u{FEFF}# T\r\n\r\n- [ ] a  \r\n  - [ ] b\r\n```\r\n- [ ] no\r\n```\r\n- [x] c @Mon"
        let once = assign(text)
        #expect(once.didChange)
        let twice = assign(once.text, seed: 99)
        #expect(twice.text == once.text)
        #expect(!twice.didChange)
        #expect(twice.tasks.map(\.id) == once.tasks.map(\.id))
        #expect(twice.noteID == once.noteID)
    }

    // MARK: Byte fidelity

    @Test func crlfDocumentsGetCRLFFrontmatterAndNoBareLineFeeds() {
        let text = "# T\r\n\r\n- [ ] a\r\n- [ ] b\r\n"
        let r = assign(text)
        #expect(masked(r.text) == "---\r\nid: N\r\n---\r\n# T\r\n\r\n- [ ] a ^T\r\n- [ ] b ^T\r\n")
        let lf = r.text.utf8.enumerated().filter { $0.element == 0x0A && ($0.offset == 0 || Array(r.text.utf8)[$0.offset - 1] != 0x0D) }
        #expect(lf.isEmpty)
    }

    @Test func crlfFrontmatterAppendKeepsCRLF() {
        let text = "---\r\ntype: note\r\n---\r\n- [ ] a\r\n"
        let r = assign(text)
        #expect(masked(r.text) == "---\r\ntype: note\r\nid: N\r\n---\r\n- [ ] a ^T\r\n")
    }

    @Test func bomIsKeptInFrontOfANewFrontmatterBlock() {
        let r = assign("\u{FEFF}# T\n- [ ] a\n")
        #expect(masked(r.text) == "\u{FEFF}---\nid: N\n---\n# T\n- [ ] a ^T\n")
        let (fm, body) = Frontmatter.parse(r.text)
        #expect(fm?.id == r.noteID)
        #expect(body.hasPrefix("# T"))
    }

    @Test func bomWithExistingFrontmatterIsKept() {
        let r = assign("\u{FEFF}---\ntype: note\n---\nx\n")
        #expect(masked(r.text) == "\u{FEFF}---\ntype: note\nid: N\n---\nx\n")
    }

    @Test func trailingWhitespaceIsPreservedAndIDGoesAtTheEnd() {
        let r = assign("- [ ] spaces   \n- [ ] tab\t\n- [ ] none\n")
        #expect(masked(r.text) == "---\nid: N\n---\n- [ ] spaces   ^T\n- [ ] tab\t^T\n- [ ] none ^T\n")
        // The extractor still reads the ids back.
        let ids = TaskExtractor(clock: FixedClock()).extract(from: r.text).compactMap(\.blockID)
        #expect(ids == r.tasks.map(\.id))
    }

    @Test func lastLineWithoutNewlineGetsNoNewline() {
        let r = assign("- [ ] a\n- [ ] b")
        #expect(masked(r.text) == "---\nid: N\n---\n- [ ] a ^T\n- [ ] b ^T")
    }

    @Test func nestedTasksAllGetIDs() {
        let text = "- [ ] parent\n    - [ ] child\n        - [x] grandchild\n\t- [ ] tabbed child\n* [ ] star\n+ [ ] plus\n"
        let r = assign(text)
        #expect(r.tasks.count == 6)
        #expect(Set(r.tasks.map(\.id)).count == 6)
        #expect(masked(r.text) == "---\nid: N\n---\n- [ ] parent ^T\n    - [ ] child ^T\n        - [x] grandchild ^T\n\t- [ ] tabbed child ^T\n* [ ] star ^T\n+ [ ] plus ^T\n")
    }

    @Test func nothingInsideCodeOrFrontmatterChanges() {
        let text = "---\nid: n-abcd\nnote: \"- [ ] not a task\"\n---\n```\n- [ ] in fence\n```\n\n    - [ ] indented code\n\n~~~md\n- [ ] tilde fence\n~~~\n- [ ] real\n"
        let r = assign(text)
        #expect(r.text == text.replacingOccurrences(of: "- [ ] real\n", with: "- [ ] real ^\(r.tasks[0].id)\n"))
        #expect(r.tasks.count == 1)
    }

    @Test func nonTaskLinesAreUntouched() {
        let text = "# H\n- plain bullet\n1. ordered\n> - [ ] quoted\ncost is 5^2\ntext ^t-abcd\n[ ] not a list\n"
        let r = assign(text)
        #expect(r.text == "---\nid: \(r.noteID!)\n---\n" + text)
        #expect(r.tasks.isEmpty)
    }

    @Test func unicodeTaskTextIsPreserved() {
        let text = "- [ ] Příliš žluťoučký kůň 🧬 @Fri\n- [ ] 日本語のタスク\n"
        let r = assign(text)
        #expect(masked(r.text) == "---\nid: N\n---\n- [ ] Příliš žluťoučký kůň 🧬 @Fri ^T\n- [ ] 日本語のタスク ^T\n")
        let extracted = TaskExtractor(clock: FixedClock()).extract(from: r.text)
        #expect(extracted.map(\.text) == ["Příliš žluťoučký kůň 🧬", "日本語のタスク"])
        #expect(extracted.first?.dueToken != nil)
    }

    @Test func emptyDocumentGetsOnlyFrontmatter() {
        let r = assign("")
        #expect(masked(r.text) == "---\nid: N\n---\n")
        #expect(r.tasks.isEmpty)
    }

    // MARK: Unsafe frontmatter

    @Test func unterminatedFrontmatterGetsNoNoteIDButTasksStillGetIDs() {
        let text = "---\ntype: note\n- [ ] a\n"
        let r = assign(text)
        guard case .skipped = r.noteOutcome else { Issue.record("expected skipped"); return }
        #expect(r.noteID == nil)
        #expect(r.text.hasPrefix("---\ntype: note\n"))
        #expect(r.tasks.count == 1)
    }

    @Test func malformedFrontmatterAndListIDsAreNotEdited() {
        let dup = "---\ntype: note\ntype: lab\n---\n- [ ] a\n"
        let r1 = assign(dup)
        guard case .skipped = r1.noteOutcome else { Issue.record("expected skipped"); return }
        #expect(r1.text.hasPrefix("---\ntype: note\ntype: lab\n---\n"))
        let listID = "---\nid: [a, b]\n---\nbody\n"
        let r2 = assign(listID)
        guard case .skipped = r2.noteOutcome else { Issue.record("expected skipped"); return }
        #expect(r2.text == listID)
    }

    // MARK: Duplicates and collisions

    @Test func aDuplicateTaskIDInOneNoteIsReassignedKeepingTheFirst() {
        let text = "- [ ] first 🧬 ^t-aaaa\n- [ ] copy ^t-aaaa  \n- [ ] other ^t-bbbb\n"
        let r = assign(text)
        #expect(r.tasks[0].id == "t-aaaa" && r.tasks[0].outcome == .kept)
        #expect(r.tasks[1].outcome == .replacedDuplicate(old: "t-aaaa"))
        #expect(r.tasks[1].id != "t-aaaa")
        let lines = r.text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.contains("- [ ] first 🧬 ^t-aaaa"))
        #expect(lines.contains("- [ ] copy ^\(r.tasks[1].id)  "))
        #expect(lines.contains("- [ ] other ^t-bbbb"))
    }

    @Test func idsAcrossNotesAreCheckedThroughTheLedger() {
        let a = "---\nid: n-same\n---\n- [ ] x ^t-dupe\n"
        let b = "---\nid: n-same\n---\n- [ ] y ^t-dupe\n"
        var ledger = IDLedger(reserved: ["n-same", "t-dupe"])
        var g = makeGenerator()
        let ra = IDAssigner().assign(to: a, ledger: &ledger, generator: &g)
        let rb = IDAssigner().assign(to: b, ledger: &ledger, generator: &g)
        #expect(ra.text == a)
        #expect(rb.noteOutcome == .replacedDuplicate(old: "n-same"))
        #expect(rb.tasks[0].outcome == .replacedDuplicate(old: "t-dupe"))
        #expect(rb.noteID != "n-same" && rb.tasks[0].id != "t-dupe")
        #expect(rb.text.contains("id: \(rb.noteID!)"))
    }

    @Test func generatedIDsAvoidIDsUsedElsewhere() {
        // Constant source always proposes t-0000 / n-0000; both are taken elsewhere.
        var g = StableIDGenerator(source: ConstantIDSource(value: 0))
        let r = IDAssigner().assign(to: "- [ ] a\n", generator: &g, existing: ["t-0000", "n-0000"])
        #expect(r.tasks[0].id != "t-0000")
        #expect(r.noteID != "n-0000")
    }

    // MARK: Extractor round trip and property test

    @Test func extractorReadsBackExactlyTheAssignedIDsWithDueDatesIntact() {
        let text = "- [ ] a @2026-10-02\n- [x] b @ Tue\n- [ ] c @before-midterm\n- [ ] d\n"
        let before = TaskExtractor(clock: FixedClock()).extract(from: text)
        let r = assign(text)
        let after = TaskExtractor(clock: FixedClock()).extract(from: r.text)
        #expect(after.map(\.blockID) == r.tasks.map(\.id))
        #expect(after.map(\.text) == before.map(\.text))
        #expect(after.map(\.dueToken) == before.map(\.dueToken))
        #expect(after.map(\.done) == before.map(\.done))
    }

    @Test func randomDocumentsKeepEverythingElseByteIdentical() {
        var rng = SplitMix64(seed: 2026)
        let pieces = [
            "# Heading\n", "text line\n", "\n", "- [ ] task a\n", "- [x] task b @Tue\n", "  - [ ] nested\n",
            "- [ ] with id ^t-abcd\n", "- [ ] foreign ^blk-1\n", "```\n- [ ] fenced\n```\n", "    - [ ] indented\n",
            "* bullet\n", "- [ ] trailing   \n", "- [ ] Příliš 🧬\n", "- [ ] crlf\r\n", "line with ^caret\n",
        ]
        for i in 0..<300 {
            var text = ""
            if i % 5 == 0 { text += "\u{FEFF}" }
            if i % 4 == 0 { text += "---\ntype: note\ntags: [a]\n---\n" }
            for _ in 0..<Int(rng.next() % 12) { text += pieces[Int(rng.next() % UInt64(pieces.count))] }
            if i % 7 == 0 { text += "- [ ] no newline at end" }
            // Fixed ids in the pieces must be unique (a duplicate is changed on purpose).
            var counter = 0
            while let r = text.range(of: "^blk-1") { counter += 1; text.replaceSubrange(r, with: "^blk-x\(counter)") }
            while let r = text.range(of: "^t-abcd") { counter += 1; text.replaceSubrange(r, with: "^t-a\(String(format: "%03d", counter))") }
            let r = assign(text, seed: UInt64(i))
            let (fm, body) = Frontmatter.parse(r.text)
            let (ofm, obody) = Frontmatter.parse(text)
            // Body identical apart from inserted task ids.
            #expect(stripInserted(body) == stripInserted(obody), "doc \(i)")
            #expect(carriageReturns(body) == carriageReturns(obody), "doc \(i)")
            // Original frontmatter keys keep their raw text.
            if let ofm { #expect(fm?.render().hasPrefix(String(ofm.render().dropLast(ofm.closing.count))) == true, "doc \(i)") }
            // Every real task now ends in an id and the note has one.
            let extracted = TaskExtractor(clock: FixedClock()).extract(from: r.text)
            #expect(extracted.allSatisfy { $0.blockID != nil }, "doc \(i)")
            #expect(fm?.id != nil, "doc \(i)")
            // Ids are unique and a second run is a no-op.
            let ids = extracted.compactMap(\.blockID)
            #expect(Set(ids).count == ids.count, "doc \(i)")
            #expect(assign(r.text, seed: 5).text == r.text, "doc \(i)")
        }
    }
}
