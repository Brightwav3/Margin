import Foundation
import Testing
@testable import MarginCore

/// M5-09: the generated sample vault holds exactly the data of `Fixtures.week5`, is valid for
/// Obsidian (plain markdown, valid YAML subset) and every wikilink resolves or is an intentional
/// "not created yet" link.
@Suite struct SampleVaultGeneratorTests {
    let world = Fixtures.week5

    /// Keeps the temp folder alive as long as the value is.
    struct Generated {
        let dir: TempDir
        let store: VaultStore
        let index: NoteIndex
        let report: SampleVaultGenerator.Report
    }

    private func generated() async throws -> Generated {
        let dir = TempDir()
        let clock = FixedClock()
        let store = try await VaultStore.open(root: dir.url, clock: clock, trash: PortableTrash())
        let report = try await SampleVaultGenerator.generate(into: store, from: world)
        let index = NoteIndex(clock: clock)
        let failures = try await index.build(from: VaultNoteSource(store: store))
        #expect(failures.isEmpty)
        return Generated(dir: dir, store: store, index: index, report: report)
    }

    @Test func countsMatchFixtures() async throws {
        let g = try await generated(); defer { withExtendedLifetime(g) {} }
        let store = g.store
        let index = g.index
        let report = g.report
        #expect(report.courseCount == 6)
        #expect(report.noteCount == world.allNotes.count)
        #expect(report.inboxCount == 5)

        let all = try await store.list()
        let semester = "\(world.semester.name)/"
        #expect(all.filter { $0.lastComponent == "_course.md" }.count == 6)
        #expect(all.filter { $0.rawValue.hasPrefix("_inbox/") }.count == 5)
        #expect(all.filter { $0.lastComponent == "_grades.md" }.count == 1)
        let noteFiles = all.filter { $0.rawValue.hasPrefix(semester) && !$0.lastComponent.hasPrefix("_") }
        #expect(noteFiles.count == world.allNotes.count)
        #expect(await index.count == all.count)

        // Every note of the fixtures is in the index with its own numbers.
        for note in world.allNotes {
            let record = try #require(await index.note(byID: note.id), "missing \(note.id)")
            #expect(record.title == note.title)
            #expect(record.kind == note.kind)
            #expect(record.date == note.date)
            #expect(record.summary.openTasks == note.openTasks, "\(note.id) open tasks")
            #expect(record.summary.totalTasks == note.totalTasks, "\(note.id) total tasks")
            #expect(record.imageCount == note.imageCount, "\(note.id) images")
            if note.wordCount > 0 { #expect(record.wordCount == note.wordCount, "\(note.id) words") }
            if !note.snippet.isEmpty { #expect(record.snippet == note.snippet, "\(note.id) snippet") }
        }
    }

    @Test func tasksMatchDueItems() async throws {
        let g = try await generated(); defer { withExtendedLifetime(g) {} }
        let index = g.index
        let tasks = await index.tasks()
        for due in world.dueItems where due.kind == .task {
            let t = try #require(tasks.first { $0.id == due.id }, "missing task \(due.id)")
            #expect(t.text == due.text)
            #expect(t.due == due.due)
            #expect(t.done == due.done)
            #expect(t.source.noteID == due.source.noteID)
        }
        // Task ids are unique across the vault.
        #expect(Set(tasks.map(\.id)).count == tasks.count)
        #expect(tasks.count == world.allNotes.reduce(0) { $0 + $1.totalTasks })
    }

    @Test func frontmatterIsValidEverywhere() async throws {
        let g = try await generated(); defer { withExtendedLifetime(g) {} }
        let store = g.store
        for path in try await store.list() {
            let text = try await store.read(path).content
            let (fm, _) = Frontmatter.parse(text)
            if path.lastComponent == "_course.md" || path.rawValue.hasPrefix("_inbox/") || path.lastComponent == "_grades.md" {
                #expect(fm != nil, "\(path) has no frontmatter")
            }
            if let fm { #expect(fm.validate().isEmpty, "\(path): \(fm.validate())") }
        }
    }

    @Test func courseFilesCarryMetadata() async throws {
        let g = try await generated(); defer { withExtendedLifetime(g) {} }
        let store = g.store
        for course in world.courses {
            let path = try VaultPath(components: [world.semester.name, course.name, "_course.md"])
            let (fm, _) = Frontmatter.parse(try await store.read(path).content)
            let front = try #require(fm)
            #expect(front.string(for: "id") == course.id)
            #expect(front.string(for: "name") == course.name)
            #expect(front.string(for: "code") == course.code)
            #expect(front.string(for: "color") == course.style.color)
            #expect(front.string(for: "icon") == course.style.icon)
            #expect((front.list(for: "sessions") ?? []).count == course.sessions.count)
            #expect((front.list(for: "exams") ?? []).count == course.exams.count)
            #expect((front.list(for: "grading") ?? []).count == course.grading.count)
        }
    }

    @Test func inboxItemsRoundTrip() async throws {
        let g = try await generated(); defer { withExtendedLifetime(g) {} }
        let store = g.store
        let paths = try await store.list(under: VaultPath("_inbox"))
        #expect(paths.count == 5)
        var seen: [String] = []
        for path in paths {
            let (fm, body) = Frontmatter.parse(try await store.read(path).content)
            let front = try #require(fm)
            let item = try #require(world.inbox.first { body.trimmingCharacters(in: .whitespacesAndNewlines) == $0.text })
            #expect(front.string(for: "captured") == item.captured.iso)
            #expect(front.string(for: "source") == item.source.rawValue)
            #expect(front.string(for: "kind") == item.kind.rawValue)
            seen.append(item.id)
        }
        #expect(Set(seen).count == 5)
    }

    @Test func everyWikilinkResolvesOrIsIntentionallyNotCreated() async throws {
        let g = try await generated(); defer { withExtendedLifetime(g) {} }
        let index = g.index
        let unresolved = Set(await index.unresolvedLinks().map(\.target))
        #expect(unresolved == world.notCreatedLinkTargets, "unresolved: \(unresolved)")
        #expect(!unresolved.isEmpty)
        // Ambiguous links would make the sample vault ask questions: there must be none.
        for record in await index.allNotes {
            for (link, resolution) in await index.outgoingLinks(ofPath: record.path) {
                if case .ambiguous(let ids) = resolution { Issue.record("\(record.path): \(link.target) is ambiguous: \(ids)") }
            }
        }
        // Backlinks work on the generated links.
        let glossary = try #require(await index.note(byID: "bio/glossary"))
        #expect(!(await index.backlinks(to: glossary.id)).isEmpty)
    }

    @Test func neverOverwritesExistingFiles() async throws {
        let g = try await generated(); defer { withExtendedLifetime(g) {} }
        let store = g.store
        await #expect(throws: MarginError.self) {
            try await SampleVaultGenerator.generate(into: store, from: world)
        }
    }

    @Test func semestersJSONDecodesToTheFixtureSemester() async throws {
        let g = try await generated(); defer { withExtendedLifetime(g) {} }
        let store = g.store
        let data = try await store.readData(VaultPath(".margin/semesters.json")).data
        let decoded = try JSONDecoder().decode([Semester].self, from: data)
        #expect(decoded == [world.semester])
    }

    @Test func fixtureBodiesAreConsistentWithTheTypedWorld() {
        // The notes that count tasks in the mockup have exactly that many task lines.
        for note in world.allNotes {
            let lines = world.taskLines(ofNote: note.id)
            #expect(lines.count == note.totalTasks, "\(note.id)")
            #expect(lines.filter { !$0.done }.count == note.openTasks, "\(note.id)")
            #expect(world.markdownBody(of: note.id) != nil)
        }
        #expect(world.markdownBody(of: "nope/nothing") == nil)
    }

    @Test func palettesMatchTheFixtureStyles() {
        for c in world.courses {
            #expect(CoursePalette.style(icon: c.style.icon, color: c.style.color) == c.style, "\(c.id)")
        }
    }
}
