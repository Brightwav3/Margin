import Foundation
import Testing
@testable import MarginCore

private let note = """
---
id: n-1
type: lecture
tags: [cells]
---
# Cell Biology

The **cell** is the basic unit of life. See [[Glossary|the glossary]] and [[Mitosis]].
Second line of the same paragraph.

## Nucleus

![[nucleus.png]]

The nucleus stores DNA, see [Wikipedia](https://example.org).

- [ ] Read chapter 2 ^t1

## Membrane

- lipid bilayer
- proteins

### Transport

Passive and active `transport`.

## Ribosomes
"""

@Suite struct NoteExcerptTests {
    @Test func firstParagraphSkipsFrontmatterAndTitle() {
        let e = NoteExcerptProvider.excerpt(of: note)
        #expect(e.text == "The cell is the basic unit of life. See the glossary and Mitosis. Second line of the same paragraph.")
        #expect(e.heading == nil)
        #expect(!e.isTruncated)
    }

    @Test func sectionAfterHeadingSkipsEmbedsAndCleansLinks() {
        let e = NoteExcerptProvider.excerpt(of: note, heading: "nucleus")
        #expect(e.text == "The nucleus stores DNA, see Wikipedia.")
        #expect(e.heading == "Nucleus")
    }

    @Test func listSectionKeepsItemsOnLines() {
        let e = NoteExcerptProvider.excerpt(of: note, heading: "Membrane")
        #expect(e.text == "• lipid bilayer\n• proteins")
    }

    @Test func sectionEndsAtNextHeadingOfSameOrHigherLevel() {
        #expect(NoteExcerptProvider.excerpt(of: note, heading: "Ribosomes").text == "")
        #expect(NoteExcerptProvider.excerpt(of: note, heading: "Ribosomes").heading == "Ribosomes")
        #expect(NoteExcerptProvider.excerpt(of: note, heading: "Transport").text == "Passive and active transport.")
    }

    @Test func diacriticsAndCaseInHeadingAreIgnored() {
        let text = "# Buňka\n\n## Jádro buňky\n\nJádro obsahuje DNA.\n"
        #expect(NoteExcerptProvider.excerpt(of: text, heading: "JADRO BUNKY").text == "Jádro obsahuje DNA.")
    }

    @Test func missingHeadingFallsBackToTheStart() {
        let e = NoteExcerptProvider.excerpt(of: note, heading: "Nonexistent")
        #expect(e.heading == nil)
        #expect(e.text.hasPrefix("The cell is"))
    }

    @Test func taskItemsAndBlockIDs() {
        let e = NoteExcerptProvider.excerpt(of: "- [ ] Read chapter 2 ^t1\n- [x] Watch video\n")
        #expect(e.text == "• Read chapter 2\n• Watch video")
    }

    @Test func codeCommentsAndRulesAreSkipped() {
        let text = "# T\n\n```swift\nlet x = 1\n```\n\n%% private %%\n\n---\n\nReal text.\n"
        #expect(NoteExcerptProvider.excerpt(of: text).text == "Real text.")
        #expect(NoteExcerptProvider.excerpt(of: "# T\n\n%%\nhidden\nlines\n%%\n\nVisible.\n").text == "Visible.")
    }

    @Test func headingInsideCodeFenceIsNotASection() {
        let text = "# T\n\n```\n## Fake\n```\n\nBody.\n\n## Real\n\nSection body.\n"
        #expect(NoteExcerptProvider.excerpt(of: text, heading: "Fake").heading == nil)
        #expect(NoteExcerptProvider.excerpt(of: text, heading: "Real").text == "Section body.")
    }

    @Test func emptyAndTitleOnlyNotes() {
        #expect(NoteExcerptProvider.excerpt(of: "").isEmpty)
        #expect(NoteExcerptProvider.excerpt(of: "# Only a title\n").isEmpty)
        #expect(NoteExcerptProvider.excerpt(of: "---\nid: x\n---\n").isEmpty)
    }

    @Test func crlfLineEndings() {
        let e = NoteExcerptProvider.excerpt(of: "---\r\nid: x\r\n---\r\n# T\r\n\r\nFirst line.\r\nSecond line.\r\n\r\nNext.\r\n")
        #expect(e.text == "First line. Second line.")
    }

    @Test func longParagraphIsCutAtAWordBoundary() {
        let text = String(repeating: "word ", count: 200)
        let e = NoteExcerptProvider.excerpt(of: text, maxLength: 50)
        #expect(e.isTruncated)
        #expect(e.text.hasSuffix("…"))
        #expect(e.text.count <= 51)
        #expect(!e.text.dropLast().hasSuffix(" "))
        #expect(NoteExcerptProvider.excerpt(of: "short", maxLength: 50).isTruncated == false)
        #expect(NoteExcerptProvider.excerpt(of: "short", maxLength: 0).text == "")
    }

    @Test func blockquoteAndOrderedList() {
        #expect(NoteExcerptProvider.excerpt(of: "> quoted *text*\n").text == "quoted text")
        #expect(NoteExcerptProvider.excerpt(of: "1. one\n2. two\n").text == "• one\n• two")
    }
}

extension PerfSuites {
    @Suite struct NoteExcerptPerf {
        /// M10-05: an excerpt in < 20 ms, also for a long note (about 100 KB) with the heading at the end.
        @Test func excerptUnder20ms() {
            var text = "---\nid: big\n---\n# Big\n\n"
            for i in 0..<120 { text += "## Section \(i)\n\n" + String(repeating: "lorem ipsum dolor sit amet ", count: 30) + "\n\n" }
            print("excerpt input: \(text.utf8.count) bytes")
            for heading in [nil, "Section 119"] as [String?] {
                let samples = perfSamples { () -> Double in
                    perfMs(ContinuousClock().measure { _ = NoteExcerptProvider.excerpt(of: text, heading: heading) })
                }
                let median = perfMedian(samples)
                print("excerpt \(heading ?? "start"): \(perfList(samples)) ms")
                #expect(median < 20, "\(heading ?? "start") median \(median) ms")
            }
        }
    }
}
