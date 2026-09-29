import Foundation
import Testing
@testable import MarginCore

private func targets() -> [LinkTarget] {
    [
        LinkTarget(id: "bio-cell", courseID: "bio", name: "Cell Biology", path: "fall-2026/bio/Cell Biology",
                   aliases: ["Cytology"], headings: ["Nucleus", "Membrane", "Mitochondria"]),
        LinkTarget(id: "bio-glossary", courseID: "bio", name: "Glossary", path: "fall-2026/bio/Glossary",
                   headings: ["A-D", "E-K"]),
        LinkTarget(id: "chem-cell", courseID: "chem", name: "Electrochemical Cell", path: "fall-2026/chem/Electrochemical Cell",
                   headings: ["Anode", "Cathode"]),
        LinkTarget(id: "chem-glossary", courseID: "chem", name: "Glossary", path: "fall-2026/chem/Glossary"),
        LinkTarget(id: "math-limits", courseID: "math", name: "Limity", path: "fall-2026/math/Limity",
                   title: "Limity funkcí", aliases: ["Limita"], headings: ["Definice", "Věty o limitách"]),
        LinkTarget(id: "bio-mitosis", courseID: "bio", name: "Mitóza", path: "fall-2026/bio/Mitóza"),
    ]
}

@Suite struct LinkSuggesterTests {
    let s = LinkSuggester(targets: targets())

    @Test func rankingPutsPrefixBeforeContains() {
        let out = s.suggest("cell")
        #expect(out.map(\.noteID).prefix(2) == ["bio-cell", "chem-cell"])   // prefix, then word-prefix
        #expect(out.last?.kind == .create)
        #expect(out.last?.insertText == "cell")
    }

    @Test func sameCourseFirst() {
        let bio = s.suggest("gloss", course: "bio")
        #expect(bio.first?.noteID == "bio-glossary")
        let chem = s.suggest("gloss", course: "chem")
        #expect(chem.first?.noteID == "chem-glossary")
    }

    @Test func equalNamesGetTheFolderInTheLink() {
        let out = s.suggest("glossary", course: "bio").filter { $0.kind == .note }
        #expect(out.map(\.insertText) == ["bio/Glossary", "chem/Glossary"])
    }

    @Test func exactNameHasNoCreateEntry() {
        #expect(!s.suggest("Mitóza").contains { $0.kind == .create })
        #expect(!s.suggest("mitoza").contains { $0.kind == .create })     // diacritics folded
        #expect(s.suggest("mitoza").first?.noteID == "bio-mitosis")
        #expect(s.suggest("Mitóz").last?.kind == .create)
    }

    @Test func titleDiffersFromFileName() {
        let out = s.suggest("limity")
        #expect(out.first?.title == "Limity funkcí")
        #expect(out.first?.insertText == "Limity")
        #expect(!out.contains { $0.kind == .create })   // the file name matches exactly
    }

    @Test func aliasInsertsPipedLink() {
        let out = s.suggest("cyto")
        #expect(out.first?.kind == .alias)
        #expect(out.first?.insertText == "Cell Biology|Cytology")
        #expect(out.first?.detail == "Cell Biology")
    }

    @Test func aliasThatIsNotBetterThanTheTitleIsNotShownTwice() {
        let out = s.suggest("limit")
        #expect(out.filter { $0.noteID == "math-limits" }.count == 1)
    }

    @Test func headingsOfAnotherNote() {
        let out = s.suggest("Cell Biology#m")
        #expect(out.map(\.title) == ["Membrane", "Mitochondria"])
        #expect(out.first?.insertText == "Cell Biology#Membrane")
        #expect(out.allSatisfy { $0.kind == .heading })
    }

    @Test func headingsOfTheCurrentNote() {
        let out = s.suggest("#nuc", note: "bio-cell")
        #expect(out.map(\.insertText) == ["#Nucleus"])
        #expect(s.suggest("#", note: "bio-cell").count == 3)
        #expect(s.suggest("#x").isEmpty)
    }

    @Test func nothingWhileTypingADisplayAlias() {
        #expect(s.suggest("Cell Biology|").isEmpty)
    }

    @Test func emptyTextListsSameCourseNotesFirstWithoutCreate() {
        let out = s.suggest("", course: "chem", note: "chem-cell")
        #expect(out.first?.noteID == "chem-glossary")
        #expect(!out.contains { $0.kind == .create })
        #expect(!out.contains { $0.noteID == "chem-cell" })
    }

    @Test func currentNoteIsNotSuggested() {
        #expect(!s.suggest("cell", note: "bio-cell").contains { $0.noteID == "bio-cell" })
    }

    @Test func limitIncludesCreate() {
        let out = s.suggest("e", limit: 3)
        #expect(out.count <= 3)
        #expect(s.suggest("zzz", limit: 1).map(\.kind) == [.create])
        #expect(s.suggest("cell", limit: 0).isEmpty)
    }

    @Test func fuzzyLetterOrderMatchesAreNotSuggested() {
        #expect(s.suggest("clbg").map(\.kind) == [.create])
    }
}

extension PerfSuites {
    @Suite struct LinkSuggesterPerf {
        /// M10-03: suggestions among 1000 notes in < 20 ms (median of 5 after a warm-up).
        @Test func suggestOn1000NotesUnder20ms() {
            let list = SearchCorpus.entries(count: 1000).map { e -> LinkTarget in
                let name = String(e.path.split(separator: "/").last!.dropLast(3))
                let course = e.path.split(separator: "/")[1]
                return LinkTarget(id: e.path, courseID: String(course), name: name, path: String(e.path.dropLast(3)),
                                  aliases: ["\(name) alias"], headings: ["Intro", "Summary", "\(name) heading"])
            }
            let suggester = LinkSuggester(targets: list)
            for q in ["mi", "deriv", "derivace int", "buňka", "cell#in", "#", "", "zzzz"] {
                let samples = perfSamples { () -> Double in
                    perfMs(ContinuousClock().measure { _ = suggester.suggest(q, course: "bio", note: list[0].id) })
                }
                let median = perfMedian(samples)
                print("link suggest '\(q)': \(perfList(samples)) ms")
                #expect(median < 20, "'\(q)' median \(median) ms")
            }
        }
    }
}
