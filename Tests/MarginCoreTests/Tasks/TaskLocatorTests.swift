import Testing
@testable import MarginCore

@Suite struct TaskLocatorTests {
    private let extractor = TaskExtractor(clock: FixedClock())

    private func tasks(_ text: String) -> [ExtractedTask] { extractor.extract(from: text) }

    private let original = """
        # Week 5

        - [ ] Read chapter 6 ^t-read
        - [ ] Write the lab report @fri
        - [x] Email the professor ^t-mail
        - [ ] Review notes
        """

    private func target(_ text: String, in note: String? = nil) throws -> TaskTarget {
        let all = tasks(note ?? original)
        let t = try #require(all.first { $0.text == text })
        return TaskTarget(blockID: t.blockID, text: t.text, line: t.line)
    }

    private func shifted(by n: Int) -> String {
        original.replacingOccurrences(of: "# Week 5\n", with: "# Week 5\n" + String(repeating: "New line\n", count: n))
    }

    @Test func blockIDSurvivesLineShiftAndTextEdit() throws {
        let t = try target("Read chapter 6")
        let edited = shifted(by: 3).replacingOccurrences(of: "Read chapter 6", with: "Read chapters 6 and 7")
        let match = try #require(TaskLocator.resolve(t, in: tasks(edited)))
        #expect(match.method == .blockID)
        #expect(match.task.text == "Read chapters 6 and 7")
        #expect(match.task.line == 3 + 3)
    }

    @Test func exactTextFollowsLineShiftWithoutID() throws {
        let t = try target("Review notes")
        for n in [1, 2, 10, 100] {
            let match = try #require(TaskLocator.resolve(t, in: tasks(shifted(by: n))))
            #expect(match.method == .exactText)
            #expect(match.task.line == 6 + n)
            #expect(match.task.text == "Review notes")
        }
    }

    @Test func lineShiftUpwardsAlsoWorks() throws {
        let t = try target("Review notes")
        let without = original.replacingOccurrences(of: "# Week 5\n\n", with: "")
        let match = try #require(TaskLocator.resolve(t, in: tasks(without)))
        #expect(match.task.line == 4 && match.method == .exactText)
    }

    @Test func doneStateAndDueChangesDoNotMatter() throws {
        let t = try target("Write the lab report")
        let edited = original.replacingOccurrences(of: "- [ ] Write the lab report @fri", with: "- [x] Write the lab report @mon")
        let match = try #require(TaskLocator.resolve(t, in: tasks(edited)))
        #expect(match.method == .exactText && match.task.done)
    }

    @Test func identicalTasksPickTheNearestToTheOldLine() {
        let note = "- [ ] Read\n- [ ] x1\n- [ ] x2\n- [ ] x3\n- [ ] x4\n- [ ] Read\n"
        let all = tasks(note)
        // Old line 5 (after an edit that removed a line above): nearest "Read" is line 6.
        let a = TaskLocator.resolve(TaskTarget(blockID: nil, text: "Read", line: 5), in: all)
        #expect(a?.task.line == 6)
        let b = TaskLocator.resolve(TaskTarget(blockID: nil, text: "Read", line: 2), in: all)
        #expect(b?.task.line == 1)
    }

    @Test func equallyNearIdenticalTasksAreAmbiguous() {
        let note = "- [ ] Read\n- [ ] other\n- [ ] Read\n"
        let r = TaskLocator.resolve(TaskTarget(blockID: nil, text: "Read", line: 2), in: tasks(note))
        #expect(r == nil)
    }

    @Test func duplicatedBlockIDPicksTheCopyNearestToTheOldLine() {
        let note = "- [ ] Pay rent ^t-rent\n- [ ] Other\n- [ ] Other 2\n- [ ] Pay rent ^t-rent\n"
        let r = TaskLocator.resolve(TaskTarget(blockID: "t-rent", text: "Pay rent", line: 5), in: tasks(note))
        #expect(r?.task.line == 4 && r?.method == .blockID)
    }

    @Test func fuzzyMatchSurvivesATypoFix() throws {
        let t = TaskTarget(blockID: nil, text: "Write the lab reprot", line: 4)
        let match = try #require(TaskLocator.resolve(t, in: tasks(shifted(by: 2))))
        #expect(match.method == .fuzzy)
        #expect(match.task.text == "Write the lab report")
        #expect(match.task.line == 6)
    }

    @Test func fuzzyIgnoresCaseAndWhitespace() throws {
        let t = TaskTarget(blockID: nil, text: "review   NOTES for exam", line: 6)
        let note = "- [ ] Review notes for exam\n"
        #expect(TaskLocator.resolve(t, in: tasks(note))?.method == .fuzzy)
    }

    @Test func dissimilarTextIsNotFound() {
        let t = TaskTarget(blockID: nil, text: "Buy groceries and cook dinner", line: 3)
        #expect(TaskLocator.resolve(t, in: tasks(original)) == nil)
    }

    @Test func idThatDisappearedFallsBackToText() throws {
        let t = TaskTarget(blockID: "t-gone", text: "Review notes", line: 6)
        let match = try #require(TaskLocator.resolve(t, in: tasks(original)))
        #expect(match.method == .exactText && match.task.line == 6)
    }

    @Test func shortTextsAreNeverFuzzy() {
        let t = TaskTarget(blockID: nil, text: "Ab1", line: 1)
        #expect(TaskLocator.resolve(t, in: tasks("- [ ] Ab2\n")) == nil)
    }

    @Test func nearEqualFuzzyCandidatesAreDecidedByDistance() throws {
        let note = "- [ ] Prepare slides for talk A\n- [ ] filler\n- [ ] filler two\n- [ ] Prepare slides for talk B\n"
        let t = TaskTarget(blockID: nil, text: "Prepare slides for talk C", line: 3)
        let match = try #require(TaskLocator.resolve(t, in: tasks(note)))
        #expect(match.task.line == 4)
    }

    @Test func targetFromItemIgnoresLocationDerivedIDs() {
        let derived = TaskItem(id: "bio/notes#L7", text: "X y z w", source: TaskLocation(noteID: "bio/notes", line: 7))
        #expect(TaskTarget(item: derived).blockID == nil)
        let real = TaskItem(id: "t-4f2a", text: "X y z w", source: TaskLocation(noteID: "bio/notes", line: 7))
        #expect(TaskTarget(item: real).blockID == "t-4f2a")
        #expect(TaskTarget(item: real).line == 7)
    }

    @Test func manyEditsAboveNeverLoseTheTask() throws {
        // 200 deterministic edits above the task: insert or delete lines; the task is always found.
        var rng = SplitMix64(seed: 7)
        var body = (1...30).map { "Line \($0)" }
        var lines = body
        lines.append("- [ ] The one that must survive")
        body = lines
        var line = body.count
        for _ in 0..<200 {
            if rng.next() % 2 == 0 || body.count < 3 {
                body.insert("Inserted \(rng.next() % 1000)", at: Int(rng.next() % UInt64(body.count - 1)))
            } else {
                body.remove(at: Int(rng.next() % UInt64(body.count - 1)))
            }
            let match = TaskLocator.resolve(TaskTarget(blockID: nil, text: "The one that must survive", line: line),
                                            in: tasks(body.joined(separator: "\n")))
            #expect(match?.task.line == body.count)
            line = match?.task.line ?? line
        }
    }
}
