import Testing
@testable import MarginCore

@Suite struct SlashCommandRegistryTests {
    static let registry = SlashCommandRegistry(clock: FixedClock())

    // kind -> (text, cursor offset in UTF-16 units)
    static let expected: [(SlashCommand.Kind, String, Int)] = [
        (.heading1, "# ", 2),
        (.heading2, "## ", 3),
        (.heading3, "### ", 4),
        (.task, "- [ ] ", 6),
        (.bullet, "- ", 2),
        (.numbered, "1. ", 3),
        (.quote, "> ", 2),
        (.callout, "> [!note] \n> ", 10),
        (.code, "```\n\n```", 4),
        (.table, "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |", 2),
        (.divider, "---\n", 4),
        (.dateToday, "2026-09-28", 10),
        (.link, "[]()", 1),
        (.embed, "![[]]", 3),
    ]

    @Test(arguments: expected)
    func insertion(kind: SlashCommand.Kind, text: String, cursor: Int) {
        let i = Self.registry.insertion(for: kind)
        #expect(i.text == text)
        #expect(i.cursorOffset == cursor)
        #expect((0...i.text.utf16.count).contains(i.cursorOffset))
    }

    @Test func everyCommandIsCoveredAndHasAnExpansion() throws {
        #expect(Self.registry.commands.count == Self.expected.count)
        for c in Self.registry.commands {
            #expect(Self.expected.contains { $0.0 == c.kind })
            #expect(try Self.registry.insertion(forID: c.id) == Self.registry.insertion(for: c.kind))
        }
        #expect(Set(Self.registry.commands.map(\.id)).count == Self.registry.commands.count)
    }

    @Test func dateFollowsTheClock() {
        let clock = FixedClock(local: LocalDateTime(date: .literal(2027, 1, 5), time: .literal(23, 59)))
        let i = SlashCommandRegistry(clock: clock).insertion(for: .dateToday)
        #expect(i == SlashInsertion(text: "2027-01-05", cursorOffset: 10))
    }

    @Test func cursorIsClampedAndUTF16() {
        #expect(SlashInsertion(text: "ab", cursorOffset: 99).cursorOffset == 2)
        #expect(SlashInsertion(text: "ab", cursorOffset: -3).cursorOffset == 0)
        #expect(SlashInsertion(endingWith: "😀").cursorOffset == 2)
    }

    @Test func matchingAndUnknownID() {
        #expect(Self.registry.matching("").count == 14)
        #expect(Self.registry.matching("task").first?.kind == .task)
        #expect(Self.registry.matching("h2").first?.kind == .heading2)
        #expect(Self.registry.matching("todo").first?.kind == .task)
        #expect(Self.registry.matching("cod").first?.kind == .code)
        #expect(Self.registry.matching("zzzz").isEmpty)
        #expect(throws: MarginError.notFound("slash command nope")) { try Self.registry.insertion(forID: "nope") }
    }
}
