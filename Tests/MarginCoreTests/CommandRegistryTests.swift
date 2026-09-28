import Testing
@testable import MarginCore

@Suite struct CommandRegistryTests {
    static let registry = CommandRegistry(commands: [
        Command(id: "note.new", title: "New note", keywords: ["create", "write"], group: "Create", shortcut: "⌘N"),
        Command(id: "task.new", title: "New task", keywords: ["todo", "create"], group: "Create", shortcut: "⇧⌘T"),
        Command(id: "course.new", title: "New course", keywords: ["class", "subject"], group: "Create"),
        Command(id: "capture", title: "Quick capture", keywords: ["inbox"], group: "Create", shortcut: "⌃⌥Space"),
        Command(id: "nav.today", title: "Go to Today", keywords: ["home"], group: "Navigate", shortcut: "⌘1"),
        Command(id: "nav.upcoming", title: "Go to Upcoming", keywords: ["calendar", "week"], group: "Navigate", shortcut: "⌘2"),
        Command(id: "nav.grades", title: "Open Grades", keywords: ["marks", "gpa"], group: "Navigate"),
        Command(id: "nav.graph", title: "Open Graph", keywords: ["links", "network"], group: "Navigate"),
        Command(id: "nav.inbox", title: "Open Inbox", group: "Navigate", shortcut: "⌘3"),
        Command(id: "sidebar", title: "Toggle sidebar", keywords: ["hide", "show"], group: "View", shortcut: "⌘\\"),
        Command(id: "inspector", title: "Toggle inspector", keywords: ["hide", "show"], group: "View", shortcut: "⌥⌘I"),
        Command(id: "search", title: "Search notes", keywords: ["find"], group: "Navigate", shortcut: "⌘K"),
        Command(id: "settings", title: "Open Settings", keywords: ["preferences"], group: "App", shortcut: "⌘,"),
        Command(id: "export", title: "Export note as PDF", keywords: ["print"], group: "Note"),
        Command(id: "daily", title: "Open daily note", group: "Navigate"),
        Command(id: "agents", title: "Manage agents", keywords: ["mcp", "identity"], group: "App"),
    ])

    /// (query, expected first result id): 20 queries.
    static let cases: [(String, String)] = [
        ("new note", "note.new"),
        ("new t", "task.new"),
        ("new c", "course.new"),
        ("today", "nav.today"),
        ("go to up", "nav.upcoming"),
        ("grad", "nav.grades"),
        ("graph", "nav.graph"),
        ("inbox", "nav.inbox"),
        ("side", "sidebar"),
        ("insp", "inspector"),
        ("sett", "settings"),
        ("pdf", "export"),
        ("prefs", "settings"),
        ("gpa", "nav.grades"),
        ("todo", "task.new"),
        ("qc", "capture"),
        ("dn", "daily"),
        ("open grad", "nav.grades"),
        ("mcp", "agents"),
        ("GRAPH", "nav.graph"),
    ]

    @Test func twentyQueries() {
        #expect(Self.cases.count == 20)
        for (q, id) in Self.cases {
            let r = Self.registry.search(q)
            #expect(r.first?.id == id, "query \(q): got \(r.map(\.id))")
        }
    }

    @Test func prefixBeatsWordStartBeatsSubsequence() {
        let reg = CommandRegistry(commands: [
            Command(id: "sub", title: "Aa bb cc dd", group: "g"),
            Command(id: "word", title: "Open Note", group: "g"),
            Command(id: "prefix", title: "Note tools", group: "g"),
        ])
        #expect(reg.search("note").map(\.id) == ["prefix", "word"])
        #expect(reg.search("abd").map(\.id) == ["sub"])
        let s = CommandRegistry.score
        #expect(s("note", "note tools")! > s("note", "open note")!)
        #expect(s("note", "open note")! > s("note", "denoted")!)
        #expect(s("note", "denoted")! > s("nte", "denoted")!)
        #expect(s("ab", "a x b")! < s("ab", "x ab")!)
    }

    @Test func recencyBoostsWithinTier() {
        let plain = Self.registry.search("open")
        let boosted = Self.registry.search("open", history: StaticCommandHistory(recentIDs: ["settings"]))
        #expect(boosted.first?.id == "settings")
        #expect(plain.first?.id != "settings")
    }

    @Test func recencyNeverBeatsBetterTier() {
        let r = Self.registry.search("new note", history: StaticCommandHistory(recentIDs: ["task.new", "course.new", "export"]))
        #expect(r.first?.id == "note.new")
    }

    @Test func emptyQueryListsRecentFirst() {
        let r = Self.registry.search("", history: StaticCommandHistory(recentIDs: ["search", "capture"]))
        #expect(r.count == Self.registry.commands.count)
        #expect(Array(r.prefix(2).map(\.id)) == ["search", "capture"])
    }

    @Test func diacriticsAndLimit() {
        let reg = CommandRegistry(commands: [Command(id: "a", title: "Přehled semestru", group: "g"),
                                             Command(id: "b", title: "Prehled", group: "g")])
        #expect(reg.search("prehled").count == 2)
        #expect(reg.search("přehled", limit: 1).count == 1)
        #expect(reg.search("zzz").isEmpty)
    }

    @Test func duplicateIDsRejected() throws {
        var reg = CommandRegistry()
        try reg.register(Command(id: "x", title: "X", group: "g"))
        #expect(throws: MarginError.invalid("duplicate command id: x")) {
            try reg.register(Command(id: "x", title: "Y", group: "g"))
        }
        #expect(reg.command(id: "x")?.title == "X")
    }
}
