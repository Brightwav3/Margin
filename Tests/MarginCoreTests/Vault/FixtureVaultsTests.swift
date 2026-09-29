import Foundation
import Testing
@testable import MarginCore

/// The committed vaults in `Tests/Fixtures/vaults/` (vault spec 05 §10): the generated week5 copy
/// must not drift from the generator, the empty vault is empty, and the Obsidian vault with its
/// quirks is read the way the spec demands.
@Suite struct FixtureVaultsTests {
    static let vaultsRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/vaults", isDirectory: true)

    private func index(of name: String) async throws -> (store: VaultStore, index: NoteIndex) {
        let store = try await VaultStore.open(root: Self.vaultsRoot.appendingPathComponent(name), clock: FixedClock(), trash: PortableTrash())
        let index = NoteIndex(clock: FixedClock())
        try await index.build(from: VaultNoteSource(store: store))
        return (store, index)
    }

    @Test func committedWeek5MatchesTheGenerator() throws {
        let root = Self.vaultsRoot.appendingPathComponent("week5")
        for file in SampleVaultGenerator.files(for: Fixtures.week5) {
            let onDisk = try #require(FileManager.default.contents(atPath: root.appendingPathComponent(file.path.rawValue).path),
                                      "missing \(file.path)")
            switch file.content {
            case .text(let t): #expect(onDisk == Data(t.utf8), "\(file.path) differs from the generator; regenerate the fixture vault")
            case .data(let d): #expect(onDisk == d, "\(file.path)")
            }
        }
        // ...and there is nothing else in it.
        let expected = Set(SampleVaultGenerator.files(for: Fixtures.week5).map(\.path.rawValue))
        let en = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var found = Set<String>()
        for case let url as URL in en where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            found.insert(String(url.path.dropFirst(root.path.count + 1)))
        }
        #expect(found == expected)
    }

    @Test func committedWeek5HasTheFixtureCounts() async throws {
        let (_, index) = try await index(of: "week5")
        let world = Fixtures.week5
        #expect(await index.count == world.allNotes.count + 6 + 1 + 5)   // notes + _course + _grades + inbox
        #expect(await index.tasks().count == world.allNotes.reduce(0) { $0 + $1.totalTasks })
    }

    @Test func emptyVaultHasNoNotes() async throws {
        let (store, index) = try await index(of: "empty")
        #expect(try await store.list().isEmpty)
        #expect(await index.count == 0)
        #expect(await index.tasks().isEmpty)
    }

    @Test func quirksVaultIndexesEveryMarkdownFileAndIgnoresTheRest() async throws {
        let (store, index) = try await index(of: "obsidian-quirks")
        let paths = try await store.list().map(\.rawValue)
        #expect(paths.contains("Projects/Thesis/Chapter 1.md"), "nested folders")
        #expect(!paths.contains { $0.hasPrefix(".obsidian") || $0.hasSuffix(".txt") || $0.hasSuffix(".png") })
        #expect(await index.count == paths.count)
        #expect(paths.count == 13)
        // Unicode names, CRLF and BOM-free frontmatter all index.
        #expect(await index.note(byPath: "Příliš žluťoučký kůň.md") != nil)
        let windows = try #require(await index.note(byPath: "Windows line endings.md"))
        #expect(windows.title == "Windows line endings")
        #expect(windows.tasks.count == 1 && windows.tasks[0].due == .literal(2026, 10, 3))
    }

    @Test func taskInsideCodeIsNotATask() async throws {
        let (_, index) = try await index(of: "obsidian-quirks")
        let note = try #require(await index.note(byPath: "Code and tasks.md"))
        #expect(note.tasks.map(\.text) == ["A real task", "A finished task", "Last real task"],
                "tasks: \(note.tasks.map(\.text))")
        #expect(note.tasks.first?.id == "real-task")
        #expect(note.tasks.map(\.done) == [false, true, false])
        // Links in code are not links either.
        #expect(note.links.isEmpty)
        // Table cells and mid-line text never make tasks.
        #expect(await index.note(byPath: "Tables.md")?.tasks.isEmpty == true)
        #expect(await index.note(byPath: "Archive/Ideas.md")?.tasks.isEmpty == true)
        // The whole vault: only the real ones.
        let all = await index.tasks().map(\.text).sorted()
        #expect(all.filter { !$0.hasPrefix("Inside an indented") } == [
            "A finished task", "A real task", "Last real task", "Review #daily notes", "Task after it", "Task before the fence",
            "Sketch the argument in one page", "Task with CRLF",
        ].sorted(), "all tasks: \(all)")
    }

    /// A 4-space indented `- [ ]` after a list and a fenced block is an indented code block
    /// (spec 05 §10: code is never a task).
    @Test func taskInsideIndentedCodeBlockIsNotATask() async throws {
        let (_, index) = try await index(of: "obsidian-quirks")
        let note = try #require(await index.note(byPath: "Indented code.md"))
        #expect(note.tasks.map(\.text) == ["Task before the fence", "Task after it"])
    }

    @Test func aliasesAndAmbiguousLinksAreReadWithoutErrors() async throws {
        let (store, index) = try await index(of: "obsidian-quirks")
        let welcome = try #require(await index.note(byPath: "Welcome.md"))
        let (fm, _) = Frontmatter.parse(try await store.read(VaultPath("Welcome.md")).content)
        let front = try #require(fm)
        #expect(front.validate().isEmpty)
        #expect(front.list(for: "aliases")?.compactMap(\.stringValue) == ["Home", "Start here"])
        #expect(welcome.tags == ["index", "quirks"])

        var results: [String: WikilinkResolution] = [:]
        for (link, resolution) in await index.outgoingLinks(ofPath: "Welcome.md") { results[link.target] = resolution }
        if case .resolved(let id)? = results["Chapter 1"] { #expect(id == "Projects/Thesis/Chapter 1") } else { Issue.record("Chapter 1: \(String(describing: results["Chapter 1"]))") }
        if case .ambiguous(let ids)? = results["Ideas"] { #expect(ids.count == 2) } else { Issue.record("Ideas: \(String(describing: results["Ideas"]))") }
        if case .resolved(let id)? = results["Archive/Ideas"] { #expect(id == "Archive/Ideas") } else { Issue.record("Archive/Ideas: \(String(describing: results["Archive/Ideas"]))") }
        if case .notCreated? = results["Not written yet"] {} else { Issue.record("Not written yet must be not-created") }
    }

    @Test func calloutsTablesAndCommentsDoNotBreakScanning() async throws {
        let (_, index) = try await index(of: "obsidian-quirks")
        let tables = try #require(await index.note(byPath: "Tables.md"))
        let targets = Set(tables.links.map(\.link.target))
        #expect(targets == ["Chapter 1", "Welcome"], "table links: \(targets)")
        let callouts = try #require(await index.note(byPath: "Callouts.md"))
        #expect(callouts.title == "Callouts")
        #expect(callouts.links.map(\.link.target) == ["Chapter 1"])
        let zoo = try #require(await index.note(byPath: "Syntax zoo.md"))
        #expect(zoo.tasks.isEmpty || zoo.tasks.count == 1)   // documented below
    }
}
