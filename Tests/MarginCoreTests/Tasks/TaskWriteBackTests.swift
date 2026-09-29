import Foundation
import Testing
@testable import MarginCore

@Suite struct TaskWriteBackTests {
    static let path = "Fall/Bio/notes.md"
    static let noteID: NoteID = "Fall/Bio/notes"

    struct Rig {
        let dir: TempDir
        let store: VaultStore
        let index: NoteIndex
        let writeBack: TaskWriteBack

        func tasks() async -> [TaskItem] { await index.note(byID: TaskWriteBackTests.noteID)?.tasks ?? [] }
        func task(_ text: String) async throws -> TaskItem {
            try #require(await tasks().first { $0.text == text })
        }
        var bytes: Data { dir.bytes(TaskWriteBackTests.path) ?? Data() }
        var text: String { String(decoding: bytes, as: UTF8.self) }
        func external(_ transform: (String) -> String) throws {
            try Data(transform(text).utf8).write(to: dir.file(TaskWriteBackTests.path))
        }
    }

    private func rig(_ content: String, maxAttempts: Int = 5, hook: (@Sendable (TempDir, Int) async -> Void)? = nil) async throws -> Rig {
        let dir = TempDir()
        try dir.seed(Self.path, Data(content.utf8))
        let store = try await VaultStore.open(root: dir.url, trash: PortableTrash())
        let index = NoteIndex(clock: FixedClock())
        try await index.build(from: VaultNoteSource(store: store))
        var afterRead: TaskWriteBack.Hook?
        if let hook {
            afterRead = { @Sendable round in await hook(dir, round) }
        }
        return Rig(dir: dir, store: store, index: index,
                   writeBack: TaskWriteBack(store: store, index: index, clock: FixedClock(),
                                            maxAttempts: maxAttempts, afterRead: afterRead))
    }

    private let note = """
        ---
        class: "[[Biology]]"
        ---
        # Notes

        - [ ] Read chapter 6 ^t-read
        - [ ] Write the lab report @fri
        - [x] Email the professor ^t-mail
        - [ ] Review notes

        """

    @Test func checksAndUnchecksExactlyOneByte() async throws {
        let r = try await rig(note)
        let before = r.bytes
        let read = try await r.task("Read chapter 6")
        let res = try await r.writeBack.setDone(true, task: read)
        #expect(res.attempts == 1 && res.method == .blockID && res.task.done)
        let after = r.bytes
        #expect(after.count == before.count)
        let changed = zip(before, after).enumerated().filter { $0.element.0 != $0.element.1 }
        #expect(changed.count == 1)
        #expect(r.text.contains("- [x] Read chapter 6 ^t-read"))
        #expect(res.entry?.beforeHash == ContentHash(of: before).hex)
        #expect(res.entry?.afterHash == ContentHash(of: after).hex)
        #expect(res.entry?.kind == .modified && res.entry?.noteID == Self.noteID)

        let again = try await r.writeBack.setDone(false, task: read)
        #expect(again.entry != nil)
        #expect(r.bytes == before)
    }

    @Test func indexSeesTheWriteAtOnce() async throws {
        let r = try await rig(note)
        _ = try await r.writeBack.setDone(true, task: try await r.task("Review notes"))
        let review = try await r.task("Review notes")
        #expect(review.done)
    }

    @Test func alreadyInTheWantedStateWritesNothing() async throws {
        let r = try await rig(note)
        let before = r.bytes
        let res = try await r.writeBack.setDone(true, task: try await r.task("Email the professor"))
        #expect(res.entry == nil)
        #expect(r.bytes == before)
    }

    @Test func bomCRLFAndNonASCIIAreKept() async throws {
        let content = "\u{FEFF}---\r\nclass: \"[[Biologie]]\"\r\n---\r\n# Příliš žluťoučký\r\n\r\n- [ ] Přečíst kapitolu 6 🧬 ^t-cz\r\n- [ ] Druhý úkol\r\n"
        let r = try await rig(content)
        let before = r.bytes
        _ = try await r.writeBack.setDone(true, task: try await r.task("Přečíst kapitolu 6 🧬"))
        #expect(r.text == content.replacingOccurrences(of: "- [ ] Přečíst", with: "- [x] Přečíst"))
        #expect(r.bytes.count == before.count)
    }

    @Test func uppercaseXCountsAsDoneAndIsUncheckedToSpace() async throws {
        let r = try await rig("# T\n\n- [X] Done thing ^t-d\n")
        let item = try await r.task("Done thing")
        #expect(item.done)
        _ = try await r.writeBack.setDone(false, task: item)
        #expect(r.text == "# T\n\n- [ ] Done thing ^t-d\n")
    }

    @Test func nestedAndOtherMarkersAreHandled() async throws {
        let r = try await rig("# T\n\n* [ ] Outer ^t-o\n    - [ ] Inner one\n+ [ ] Plus\n")
        _ = try await r.writeBack.setDone(true, task: try await r.task("Inner one"))
        _ = try await r.writeBack.setDone(true, task: try await r.task("Plus"))
        #expect(r.text == "# T\n\n* [ ] Outer ^t-o\n    - [x] Inner one\n+ [x] Plus\n")
    }

    // MARK: Concurrency

    @Test func twoRapidTogglesDoNotCorruptTheFile() async throws {
        let r = try await rig(note)
        let a = try await r.task("Read chapter 6")
        let b = try await r.task("Write the lab report")
        async let x = r.writeBack.setDone(true, task: a)
        async let y = r.writeBack.setDone(true, task: b)
        _ = try await (x, y)
        let expected = note
            .replacingOccurrences(of: "- [ ] Read chapter 6", with: "- [x] Read chapter 6")
            .replacingOccurrences(of: "- [ ] Write the lab report", with: "- [x] Write the lab report")
        #expect(r.text == expected)
    }

    @Test func twoRapidTogglesOfTheSameTaskEndInOneOfTheTwoStates() async throws {
        for _ in 0..<10 {
            let r = try await rig(note)
            let a = try await r.task("Read chapter 6")
            async let x = r.writeBack.setDone(true, task: a)
            async let y = r.writeBack.setDone(false, task: a)
            _ = try await (x, y)
            let lines = r.text.components(separatedBy: "\n")
            let others = note.components(separatedBy: "\n").enumerated().filter { $0.offset != 5 }.map(\.element)
            #expect(lines.enumerated().filter { $0.offset != 5 }.map(\.element) == others)
            #expect(lines[5] == "- [x] Read chapter 6 ^t-read" || lines[5] == "- [ ] Read chapter 6 ^t-read")
        }
    }

    @Test func manyConcurrentTogglesAllLand() async throws {
        let count = 40
        let body = (1...count).map { "- [ ] Task number \($0) ^t-\($0)" }.joined(separator: "\n")
        let r = try await rig("# Many\n\n" + body + "\n")
        let items = await r.tasks()
        #expect(items.count == count)
        try await withThrowingTaskGroup(of: TaskWriteResult.self) { group in
            for item in items { group.addTask { try await r.writeBack.setDone(true, task: item) } }
            for try await _ in group {}
        }
        let expected = "# Many\n\n" + (1...count).map { "- [x] Task number \($0) ^t-\($0)" }.joined(separator: "\n") + "\n"
        #expect(r.text == expected)
        #expect(await r.tasks().allSatisfy(\.done))
    }

    // MARK: Edits from outside

    @Test func externalEditBetweenReadAndWriteIsHandledByRetry() async throws {
        let r = try await rig(note) { dir, round in
            guard round == 1 else { return }
            // Someone inserts three lines above the task between our read and our write.
            let url = dir.file(Self.path)
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? Data(text.replacingOccurrences(of: "# Notes\n", with: "# Notes\n\nNew paragraph\nAnother one\n").utf8).write(to: url)
        }
        let item = try await r.task("Write the lab report")
        let res = try await r.writeBack.setDone(true, task: item)
        #expect(res.attempts == 2)
        #expect(r.text.contains("New paragraph\nAnother one\n"))
        #expect(r.text.contains("- [x] Write the lab report @fri"))
        #expect(r.text.contains("- [ ] Read chapter 6 ^t-read"))
        #expect(res.task.source.line == item.source.line + 3)
    }

    @Test func staleTaskLineIsResolvedAgainstTheCurrentFile() async throws {
        let r = try await rig(note)
        let item = try await r.task("Review notes")           // line 9
        try r.external { $0.replacingOccurrences(of: "# Notes\n", with: "# Notes\n\nOne\nTwo\nThree\n") }
        let res = try await r.writeBack.setDone(true, task: item)
        #expect(res.attempts == 1 && res.method == .exactText)
        #expect(r.text.contains("- [x] Review notes"))
        #expect(r.text.contains("- [ ] Read chapter 6 ^t-read") && r.text.contains("- [ ] Write the lab report"))
    }

    @Test func taskDeletedFromOutsideIsNotFoundAndFileStaysAsTheOtherProgramLeftIt() async throws {
        let r = try await rig(note)
        let item = try await r.task("Review notes")
        try r.external { $0.replacingOccurrences(of: "- [ ] Review notes\n", with: "") }
        let external = r.bytes
        do { _ = try await r.writeBack.setDone(true, task: item); Issue.record("should throw") }
        catch let e as MarginError { #expect(e.code == "notFound") }
        #expect(r.bytes == external)
    }

    @Test func aFileThatKeepsChangingEndsInConflictWithoutDamage() async throws {
        let r = try await rig(note, maxAttempts: 3) { dir, round in
            let url = dir.file(Self.path)
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? Data((text + "external \(round)\n").utf8).write(to: url)
        }
        let item = try await r.task("Review notes")
        do { _ = try await r.writeBack.setDone(true, task: item); Issue.record("should throw") }
        catch let e as MarginError { #expect(e.code == "conflict") }
        #expect(r.text == note + "external 1\nexternal 2\nexternal 3\n")
    }

    @Test func staleBaseVersionIsAConflict() async throws {
        let r = try await rig(note)
        let item = try await r.task("Review notes")
        do {
            _ = try await r.writeBack.setDone(true, task: item, baseVersion: ContentHash(of: "old").hex)
            Issue.record("should throw")
        } catch let e as MarginError { #expect(e.code == "conflict") }
        let current = ContentHash(of: r.bytes).hex
        let ok = try await r.writeBack.setDone(true, task: item, baseVersion: current)
        #expect(ok.entry != nil)
    }

    // MARK: Other

    @Test func dryRunChangesNothing() async throws {
        let r = try await rig(note)
        let before = r.bytes
        let res = try await r.writeBack.setDone(true, task: try await r.task("Review notes"), dryRun: true)
        #expect(res.entry?.afterHash != nil && res.entry?.afterHash != res.entry?.beforeHash)
        #expect(r.bytes == before)
        let after = try await r.task("Review notes")
        #expect(after.done == false)
    }

    @Test func examsAndUnknownNotesAreRejected() async throws {
        let r = try await rig(note)
        let exam = TaskItem(id: "exam-x", text: "Midterm", kind: .exam, source: TaskLocation(noteID: "bio/_course", line: 1))
        do { _ = try await r.writeBack.setDone(true, task: exam); Issue.record("should throw") }
        catch let e as MarginError { #expect(e.code == "invalid") }
        let ghost = TaskItem(id: "t-x", text: "Ghost", source: TaskLocation(noteID: "nope/nothing", line: 1))
        do { _ = try await r.writeBack.setDone(true, task: ghost); Issue.record("should throw") }
        catch let e as MarginError { #expect(e.code == "notFound") }
    }

    @Test func setterTouchesNothingOutsideTheCheckbox() throws {
        let content = "- [ ] a [ ] b\n"
        let task = TaskExtractor(clock: FixedClock()).extract(from: content)[0]
        #expect(TaskWriteBack.setting(true, in: content, task: task) == "- [x] a [ ] b\n")
        #expect(TaskWriteBack.setting(false, in: content, task: task) == content)
    }
}
