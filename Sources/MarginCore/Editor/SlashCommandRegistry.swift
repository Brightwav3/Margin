/// Text to insert for a slash command and where the caret goes afterwards.
public struct SlashInsertion: Sendable, Hashable {
    public var text: String
    /// Caret position as a UTF-16 offset inside `text` (0...text.utf16.count), the unit used by
    /// `NSRange` / `NSTextView`.
    public var cursorOffset: Int

    public init(text: String, cursorOffset: Int) {
        self.text = text
        self.cursorOffset = min(max(0, cursorOffset), text.utf16.count)
    }

    /// Caret after the last inserted character.
    public init(endingWith text: String) { self.init(text: text, cursorOffset: text.utf16.count) }
}

/// One entry of the `/` menu (mockup 2a, section Blocks).
///
/// The editor removes the typed `/query` itself and inserts `insertion` at that position; the
/// text always starts at the beginning of a line except `date`, `link` and `embed`, which are
/// inline.
public struct SlashCommand: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case heading1, heading2, heading3, task, bullet, numbered, quote, callout, code, table
        case divider, dateToday, link, embed
    }

    public var kind: Kind
    public var id: String { kind.rawValue }
    public var title: String
    public var keywords: [String]
    /// Menu section: `Blocks` or `Inline`.
    public var group: String

    public init(kind: Kind, title: String, keywords: [String] = [], group: String = "Blocks") {
        self.kind = kind; self.title = title; self.keywords = keywords; self.group = group
    }
}

/// The fixed set of slash commands and their expansion. Pure: "today" comes from the `Clock`.
public struct SlashCommandRegistry: Sendable {
    public let commands: [SlashCommand]
    private let clock: any Clock

    public init(clock: any Clock) {
        self.clock = clock
        self.commands = [
            SlashCommand(kind: .heading1, title: "Heading 1", keywords: ["h1", "title"]),
            SlashCommand(kind: .heading2, title: "Heading 2", keywords: ["h2", "subtitle"]),
            SlashCommand(kind: .heading3, title: "Heading 3", keywords: ["h3"]),
            SlashCommand(kind: .task, title: "Task", keywords: ["todo", "checkbox", "checklist"]),
            SlashCommand(kind: .bullet, title: "Bullet list", keywords: ["ul", "unordered"]),
            SlashCommand(kind: .numbered, title: "Numbered list", keywords: ["ol", "ordered"]),
            SlashCommand(kind: .quote, title: "Quote", keywords: ["blockquote"]),
            SlashCommand(kind: .callout, title: "Callout", keywords: ["note", "info", "admonition"]),
            SlashCommand(kind: .code, title: "Code block", keywords: ["fence", "snippet"]),
            SlashCommand(kind: .table, title: "Table", keywords: ["grid"]),
            SlashCommand(kind: .divider, title: "Divider", keywords: ["hr", "rule", "line"]),
            SlashCommand(kind: .dateToday, title: "Date today", keywords: ["date", "now", "day"], group: "Inline"),
            SlashCommand(kind: .link, title: "Link", keywords: ["url", "href"], group: "Inline"),
            SlashCommand(kind: .embed, title: "Embed", keywords: ["transclude", "include"], group: "Inline"),
        ]
    }

    public func command(id: String) -> SlashCommand? { commands.first { $0.id == id } }

    /// Commands matching what was typed after `/` (same fuzzy tiers as the command palette).
    /// An empty query returns all commands in menu order.
    public func matching(_ query: String) -> [SlashCommand] {
        let q = CommandRegistry.fold(query)
        if q.isEmpty { return commands }
        var scored: [(SlashCommand, Int, Int)] = []
        for (i, c) in commands.enumerated() {
            var best = CommandRegistry.score(q, in: CommandRegistry.fold(c.title))
            for k in c.keywords {
                if let s = CommandRegistry.score(q, in: CommandRegistry.fold(k)) { best = max(best ?? 0, min(s * 3 / 4, 590)) }
            }
            if let best { scored.append((c, best, i)) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }.map(\.0)
    }

    /// Expansion of `kind`.
    public func insertion(for kind: SlashCommand.Kind) -> SlashInsertion {
        switch kind {
        case .heading1: SlashInsertion(endingWith: "# ")
        case .heading2: SlashInsertion(endingWith: "## ")
        case .heading3: SlashInsertion(endingWith: "### ")
        case .task: SlashInsertion(endingWith: "- [ ] ")
        case .bullet: SlashInsertion(endingWith: "- ")
        case .numbered: SlashInsertion(endingWith: "1. ")
        case .quote: SlashInsertion(endingWith: "> ")
        case .callout: SlashInsertion(endingWith: "> [!note] \n> ").withCursor(after: "> [!note] ")
        case .code: SlashInsertion(text: "```\n\n```", cursorOffset: 4)
        case .table: SlashInsertion(text: "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |", cursorOffset: 2)
        case .divider: SlashInsertion(endingWith: "---\n")
        case .dateToday: SlashInsertion(endingWith: clock.today.iso)
        case .link: SlashInsertion(text: "[]()", cursorOffset: 1)
        case .embed: SlashInsertion(text: "![[]]", cursorOffset: 3)
        }
    }

    /// Expansion of the command with `id`, or `.notFound`.
    public func insertion(forID id: String) throws(MarginError) -> SlashInsertion {
        guard let c = command(id: id) else { throw .notFound("slash command \(id)") }
        return insertion(for: c.kind)
    }
}

extension SlashInsertion {
    fileprivate func withCursor(after prefix: String) -> SlashInsertion {
        SlashInsertion(text: text, cursorOffset: prefix.utf16.count)
    }
}
