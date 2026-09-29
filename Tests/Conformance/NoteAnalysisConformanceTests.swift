import Foundation
import Testing
@testable import MarginCore

/// One suite, run against `FixtureNoteAnalysis` and `VaultNoteAnalysis` (contract §5).
@Suite struct NoteAnalysisConformanceTests {
    let world = Fixtures.week5
    let lecture8 = "bio/lecture-8"

    private func lineNumber(of needle: String, in text: String) -> Int? {
        text.split(separator: "\n", omittingEmptySubsequences: false).firstIndex { $0 == needle }.map { $0 + 1 }
    }

    // MARK: Outline

    @Test(arguments: HarnessKind.allCases)
    func outlineIsTheHeadingsOfTheBodyWithBodyLines(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            for summary in world.allNotes {
                let body = try await h.notes.open(id: summary.id).text
                let expected = MarkdownScanner().scan(body).headings.map { OutlineItem(level: $0.level, text: $0.text, line: $0.line) }
                let outline = try await h.analysis.outline(id: summary.id)
                #expect(outline == expected, "\(summary.id)")
                #expect(outline.first?.line == 1 && outline.first?.level == 1, "\(summary.id) starts with the H1")
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func outlineIgnoresCodeAndFollowsSaves(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let text = "# Title\n\n```\n# not a heading\n```\n\n## Second ##\n\n### Third\n"
            _ = try await h.notes.save(id: lecture8, text: text, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let outline = try await h.analysis.outline(id: lecture8)
            #expect(outline == [
                OutlineItem(level: 1, text: "Title", line: 1), OutlineItem(level: 2, text: "Second", line: 7),
                OutlineItem(level: 3, text: "Third", line: 9),
            ])
        }
    }

    // MARK: Links

    @Test(arguments: HarnessKind.allCases)
    func outgoingListsEveryLinkIncludingNotCreatedOnes(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            var notCreated = Set<String>()
            for summary in world.allNotes {
                let links = try await h.analysis.outgoing(id: summary.id)
                #expect(links.map(\.target) == world.relatedLinkTargets(of: summary), "\(summary.id)")
                for link in links {
                    switch link.state {
                    case .resolved:
                        #expect(link.noteID != nil && link.title != nil && link.candidates.isEmpty)
                    case .notCreated:
                        notCreated.insert(link.target)
                        #expect(link.noteID == nil)
                    case .ambiguous, .selfLink:
                        Issue.record("unexpected \(link.state) in \(summary.id)")
                    }
                }
            }
            #expect(notCreated == world.notCreatedLinkTargets)
            #expect(!notCreated.isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func backlinksCarryTheSourceAndItsLine(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            struct Hit: Hashable { var source: NoteID; var line: Int; var context: String }
            var expected: [NoteID: Set<Hit>] = [:]
            for source in world.allNotes {
                let body = try await h.notes.open(id: source.id).text
                for target in world.relatedLinkTargets(of: source) {
                    guard let note = world.allNotes.first(where: { $0.title == target }), note.id != source.id else { continue }
                    let line = try #require(lineNumber(of: "- [[\(target)]]", in: body))
                    expected[note.id, default: []].insert(Hit(source: source.id, line: line, context: "- [[\(target)]]"))
                }
            }
            #expect(!expected.isEmpty)
            for note in world.allNotes {
                let links = try await h.analysis.backlinks(id: note.id)
                #expect(Set(links.map { Hit(source: $0.sourceNoteID, line: $0.line, context: $0.context) }) == expected[note.id, default: []],
                        "\(note.id)")
                #expect(links.count == expected[note.id, default: []].count)
                // Sorted by source title, case-insensitive.
                #expect(links.map { $0.sourceTitle.lowercased() } == links.map { $0.sourceTitle.lowercased() }.sorted())
                for link in links { #expect(link.sourceTitle == world.allNotes.first { $0.id == link.sourceNoteID }?.title) }
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func analysisFollowsWrites(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.analysis.backlinks(id: "bio/glossary")
            let text = "# Lecture 8\n\nSee [[Glossary]] and [[Nowhere yet|somewhere]].\n\n- [[Glossary#Terms]]\n"
            _ = try await h.notes.save(id: lecture8, text: text, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)

            let after = try await h.analysis.backlinks(id: "bio/glossary")
            let mine = after.filter { $0.sourceNoteID == lecture8 }
            #expect(mine.map(\.line) == [3, 5])
            #expect(mine.map(\.context) == ["See [[Glossary]] and [[Nowhere yet|somewhere]].", "- [[Glossary#Terms]]"])
            #expect(after.count == before.filter { $0.sourceNoteID != lecture8 }.count + 2)

            let links = try await h.analysis.outgoing(id: lecture8)
            #expect(links.map(\.target) == ["Glossary", "Nowhere yet", "Glossary"])
            #expect(links.map(\.state) == [.resolved, .notCreated, .resolved])
            #expect(links[1].alias == "somewhere" && links[2].heading == "Terms")
            #expect(links.map(\.line) == [3, 3, 5])
            #expect(links[0].noteID == "bio/glossary")
        }
    }

    // MARK: Stats

    @Test(arguments: HarnessKind.allCases)
    func statsMatchTheNoteText(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            for summary in try await h.notes.notes(course: nil) {
                let stats = try await h.analysis.stats(id: summary.id)
                let body = try await h.notes.open(id: summary.id).text
                let counts = NoteStatsCalculator.count(body: body)
                #expect(stats.words == NoteIndex.wordCount(body), "\(summary.id) words")
                #expect(stats.openTasks == counts.openTasks && stats.totalTasks == counts.totalTasks, "\(summary.id) tasks")
                #expect(stats.backlinks == (try await h.analysis.backlinks(id: summary.id)).count, "\(summary.id) backlinks")
                #expect(stats.properties == (try await h.analysis.properties(id: summary.id)).count, "\(summary.id) properties")
            }
            let s = try await h.analysis.stats(id: lecture8)
            #expect(s.properties == 4 && s.words == 412)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func statsDescribeEditorTextWhenGiven(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let saved = try await h.analysis.stats(id: lecture8)
            let text = "# Draft\n\nthree words here\n\n- [ ] open one\n- [x] done one\n- [ ] open two\n\n```\n- [ ] code\n```\n"
            let live = try await h.analysis.stats(id: lecture8, text: text)
            #expect(live.words == NoteIndex.wordCount(text))
            #expect(live.openTasks == 2 && live.totalTasks == 3)
            #expect(live.backlinks == saved.backlinks && live.properties == saved.properties)
            // The saved note is untouched by asking about editor text.
            #expect(try await h.analysis.stats(id: lecture8) == saved)
            // Asking again with an edit gives the new numbers.
            let edited = try await h.analysis.stats(id: lecture8, text: text + "- [ ] another\n")
            #expect(edited.openTasks == 3 && edited.totalTasks == 4)
        }
    }

    // MARK: Properties

    @Test(arguments: HarnessKind.allCases)
    func propertiesComeInFileOrderWithTypes(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let props = try await h.analysis.properties(id: lecture8)
            #expect(props.map(\.key) == ["id", "date", "class", "type"])
            #expect(props.map(\.type) == [.text, .date, .link, .text])
            #expect(props[1].value == .date(.literal(2026, 9, 24)))
            #expect(props[2].value == .string("[[Cell Biology]]"))
            #expect(props[3].value == .string("lecture"))

            _ = try await h.properties.set(key: "mood", value: .string("calm"), on: lecture8, actor: .user, baseVersion: nil,
                                           dryRun: false, idempotencyKey: nil)
            _ = try await h.properties.set(key: "Rating", value: .number(4), on: lecture8, actor: .user, baseVersion: nil,
                                           dryRun: false, idempotencyKey: nil)
            _ = try await h.properties.remove(key: "date", on: lecture8, actor: .user, baseVersion: nil, dryRun: false,
                                              idempotencyKey: nil)
            let after = try await h.analysis.properties(id: lecture8)
            #expect(after.map(\.key) == ["id", "class", "type", "mood", "Rating"])
            #expect(after.map(\.type) == [.text, .link, .text, .text, .number])
            #expect(try await h.analysis.stats(id: lecture8).properties == 5)
        }
    }

    // MARK: Errors

    @Test(arguments: HarnessKind.allCases)
    func unknownNoteIsNotFound(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let a = h.analysis
            let calls: [(String, @Sendable () async throws -> Void)] = [
                ("outline", { _ = try await a.outline(id: "bio/nope") }),
                ("backlinks", { _ = try await a.backlinks(id: "bio/nope") }),
                ("outgoing", { _ = try await a.outgoing(id: "bio/nope") }),
                ("stats", { _ = try await a.stats(id: "bio/nope") }),
                ("stats(text)", { _ = try await a.stats(id: "bio/nope", text: "x") }),
                ("properties", { _ = try await a.properties(id: "bio/nope") }),
            ]
            for (name, call) in calls {
                do {
                    try await call()
                    Issue.record("\(name): expected notFound")
                } catch let error as MarginError {
                    if case .notFound = error {} else { Issue.record("\(name): \(error)") }
                }
            }
        }
    }
}
