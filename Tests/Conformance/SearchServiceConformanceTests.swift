import Foundation
import Testing
@testable import MarginCore

/// One suite, run against `FixtureSearchService` and `VaultSearchService` (contract §5).
@Suite struct SearchServiceConformanceTests {
    let lecture8 = "bio/lecture-8"

    private func ids(_ hits: [SearchHit]) -> [NoteID] { hits.map(\.id) }

    /// Polls `body` until it returns true (outside edits reach the vault through the watcher).
    private func eventually(timeout: TimeInterval = 20, _ body: () async throws -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await body() { return true }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    // MARK: Words

    @Test(arguments: HarnessKind.allCases)
    func caseAndDiacriticsAreIgnoredAndAllWordsMustMatch(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let upper = try await h.search.search(query: "CHOLESTEROL")
            #expect(ids(upper) == [lecture8])
            #expect(try await h.search.search(query: "cholesterol fluid").map(\.id) == [lecture8])
            #expect(try await h.search.search(query: "cholesterol zzzznotaword").isEmpty)
            // Text written with diacritics is found without them.
            _ = try await h.notes.save(id: lecture8, text: "# Lecture 8\n\nMitóza a meióza: dělení buněk.\n", actor: .user,
                                       baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(try await h.search.search(query: "mitoza deleni bunek").map(\.id) == [lecture8])
            #expect(try await h.search.search(query: "MITÓZA").map(\.id) == [lecture8])
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func lastWordMatchesAsPrefixUnlessFollowedBySpace(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let typing = ids(try await h.search.search(query: "membr"))
            let finished = ids(try await h.search.search(query: "membr "))
            let whole = ids(try await h.search.search(query: "membrane"))
            #expect(typing.contains(lecture8))
            #expect(!finished.contains(lecture8))
            #expect(whole.contains(lecture8))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func titleMatchesRankBeforeTextMatches(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let hits = try await h.search.search(query: "membrane")
            #expect(hits.count >= 2)
            // "Lecture 9 — Membrane transport", "Membrane transport summary" have it in the title;
            // Lecture 8 has "Cell membrane" in its title as well, so every hit has it there.
            #expect(hits.allSatisfy { $0.title.lowercased().contains("membrane") || $0.score > 0 })
            #expect(zip(hits, hits.dropFirst()).allSatisfy { $0.score >= $1.score })
            let ties = zip(hits, hits.dropFirst()).filter { $0.score == $1.score }
            #expect(ties.allSatisfy { ($0.title.lowercased(), $0.id) <= ($1.title.lowercased(), $1.id) })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func highlightsPointAtTheQueryWords(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let hits = try await h.search.search(query: "cholesterol")
            let hit = try #require(hits.first)
            #expect(hit.snippet.lowercased().contains("cholesterol"))
            #expect(!hit.snippet.contains("\n"))
            #expect(!hit.highlights.isEmpty)
            let chars = Array(hit.snippet)
            for r in hit.highlights {
                #expect(r.location >= 0 && r.length > 0 && r.location + r.length <= chars.count)
                #expect(String(chars[r.location..<(r.location + r.length)]).lowercased() == "cholesterol")
            }
            let titleHit = try #require(try await h.search.search(query: "membrane").first { $0.id == lecture8 })
            let title = Array(titleHit.title)
            #expect(titleHit.titleHighlights.count == 1)
            let r = try #require(titleHit.titleHighlights.first)
            #expect(String(title[r.location..<(r.location + r.length)]).lowercased() == "membrane")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func hitsCarryTheNoteSummaryFields(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let summaries = try await h.notes.notes(course: nil)
            for hit in try await h.search.search(query: "lecture") {
                let s = try #require(summaries.first { $0.id == hit.id }, "\(hit.id)")
                #expect(hit.title == s.title && hit.courseID == s.courseID && hit.kind == s.kind && hit.date == s.date)
            }
        }
    }

    // MARK: Filters

    @Test(arguments: HarnessKind.allCases)
    func filtersNarrowTheResult(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let all = try await h.search.search(query: "lecture")
            #expect(all.count > 3)
            let bio = try await h.search.search(query: "lecture", filter: SearchFilter(course: "bio"))
            #expect(!bio.isEmpty && bio.allSatisfy { $0.courseID == "bio" })
            #expect(Set(ids(bio)) == Set(all.filter { $0.courseID == "bio" }.map(\.id)))
            #expect(try await h.search.search(query: "lecture", filter: SearchFilter(course: "no-such-course")).isEmpty)

            let labs = try await h.search.search(query: "", filter: SearchFilter(kind: .lab))
            #expect(!labs.isEmpty && labs.allSatisfy { $0.kind == .lab })

            let from = try #require(LocalDate(iso: "2026-09-21"))
            let to = try #require(LocalDate(iso: "2026-09-24"))
            let ranged = try await h.search.search(query: "", filter: SearchFilter(from: from, to: to))
            #expect(!ranged.isEmpty)
            #expect(ranged.allSatisfy { ($0.date.map { $0 >= from && $0 <= to }) == true })
            #expect(Set(ids(ranged)) == ["bio/lecture-8", "bio/lecture-7", "bio/lab-2"])
            let wordAndDate = try await h.search.search(query: "nucleus", filter: SearchFilter(from: from, to: to))
            #expect(ids(wordAndDate).allSatisfy { ["bio/lecture-8", "bio/lecture-7", "bio/lab-2"].contains($0) })
            #expect(ids(wordAndDate).contains("bio/lecture-7"))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func tagFilterNeedsEveryTag(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.properties.set(key: "tags", value: .list([.string("exam"), .string("Cells")]), on: lecture8,
                                           actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            _ = try await h.properties.set(key: "tags", value: .list([.string("exam")]), on: "bio/lecture-7",
                                           actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let exam = try await h.search.search(query: "", filter: SearchFilter(tags: ["#EXAM"]))
            #expect(Set(ids(exam)) == [lecture8, "bio/lecture-7"])
            let both = try await h.search.search(query: "lecture", filter: SearchFilter(tags: ["exam", "cells"]))
            #expect(ids(both) == [lecture8])
            #expect(try await h.search.search(query: "", filter: SearchFilter(tags: ["exam", "nope"])).isEmpty)
            // Tags are searchable words as well.
            let byTag = ids(try await h.search.search(query: "cells"))
            #expect(byTag.contains(lecture8))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func limitAndEmptyQueryRules(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            #expect(try await h.search.search(query: "").isEmpty)
            #expect(try await h.search.search(query: "   ").isEmpty)
            #expect(try await h.search.search(query: "lecture", filter: SearchFilter(limit: 2)).count == 2)
            // A filter without words lists notes in the order of `NoteRepository.notes`.
            let listed = try await h.search.search(query: "", filter: SearchFilter(course: "bio"))
            let expected = try await h.notes.notes(course: "bio")
            #expect(ids(listed) == expected.map(\.id))
            #expect(listed.allSatisfy { $0.score == 0 && $0.highlights.isEmpty })
            await #expect(throws: MarginError.self) { try await h.search.search(query: "x", filter: SearchFilter(limit: 0)) }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func onlyLiveNotesAreSearched(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            // Course files and the inbox are not notes.
            let hits = try await h.search.search(query: "okafor")
            #expect(hits.isEmpty)
            let notes = Set(try await h.notes.notes(course: nil).map(\.id))
            for hit in try await h.search.search(query: "a") { #expect(notes.contains(hit.id)) }
        }
    }

    // MARK: Freshness

    @Test(arguments: HarnessKind.allCases)
    func resultsFollowSavesAndOutsideEdits(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            #expect(try await h.search.search(query: "zyxwvu").isEmpty)
            _ = try await h.notes.save(id: lecture8, text: "# Lecture 8\n\nThe zyxwvu effect.\n", actor: .user,
                                       baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(try await h.search.search(query: "zyxwvu").map(\.id) == [lecture8])
            #expect(try await h.search.search(query: "cholesterol").isEmpty)

            try await h.editNote("bio/lecture-7", "# Lecture 7\n\nA qwertzu appears.\n")
            #expect(try await eventually { try await h.search.search(query: "qwertzu").map(\.id) == ["bio/lecture-7"] })

            try await h.deleteNote("bio/lecture-7")
            #expect(try await eventually { try await h.search.search(query: "qwertzu").isEmpty })
        }
    }

    // MARK: Links

    @Test(arguments: HarnessKind.allCases)
    func linkSuggestionsRankTheCurrentCourseFirst(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let out = try await h.search.suggestLinks(prefix: "lect", course: "bio", note: lecture8)
            let notes = out.filter { $0.kind == .note }
            #expect(notes.count >= 3)
            #expect(notes.allSatisfy { $0.courseID == "bio" })
            #expect(!notes.contains { $0.noteID == lecture8 })
            #expect(out.last?.kind == .create)
            #expect(out.last?.insertText == "lect")
            #expect(out.count <= 8)
            #expect(try await h.search.suggestLinks(prefix: "lect", course: "bio", note: nil, limit: 2).count == 2)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func linkSuggestionsOfAnExistingNameHaveNoCreateEntryAndOfferHeadings(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.notes.save(id: lecture8, text: "# Lecture 8\n\n## Bilayer\n\nText.\n\n## Transport\n", actor: .user,
                                       baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let exact = try await h.search.suggestLinks(prefix: "Glossary")
            #expect(exact.first?.noteID == "bio/glossary")
            #expect(!exact.contains { $0.kind == .create })
            let headings = try await h.search.suggestLinks(prefix: "Lecture 8#", course: nil, note: nil)
            #expect(headings.map(\.title) == ["Bilayer", "Transport"])
            #expect(headings.map(\.insertText).allSatisfy { $0.hasSuffix("#Bilayer") || $0.hasSuffix("#Transport") })
            #expect(headings.allSatisfy { $0.kind == .heading && $0.noteID == lecture8 })
            let own = try await h.search.suggestLinks(prefix: "#tr", course: "bio", note: lecture8)
            #expect(own.map(\.insertText) == ["#Transport"])
            await #expect(throws: MarginError.self) { try await h.search.suggestLinks(prefix: "x", course: nil, note: nil, limit: 0) }
        }
    }

    // MARK: Excerpts

    @Test(arguments: HarnessKind.allCases)
    func excerptIsTheFirstParagraphWithoutFrontmatter(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.notes.save(
                id: lecture8, text: "# Lecture 8\n\nFirst **paragraph** with [[Glossary]].\n\n## Details\n\nDetail text.\n",
                actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let e = try await h.search.excerpt(note: lecture8)
            #expect(e.text == "First paragraph with Glossary.")
            #expect(e.heading == nil && !e.isTruncated)
            let d = try await h.search.excerpt(note: lecture8, heading: "details")
            #expect(d.text == "Detail text." && d.heading == "Details")
            let raw = try await h.rawContent(lecture8)
            if raw.hasPrefix("---") { #expect(!e.text.contains("id:")) }
            await #expect(throws: MarginError.self) { try await h.search.excerpt(note: "bio/no-such-note") }
        }
    }
}
