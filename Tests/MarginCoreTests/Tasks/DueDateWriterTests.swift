import Foundation
import Testing
@testable import MarginCore

/// M10-10.B: writing and replacing the `@…` due token of a task line.
@Suite struct DueDateWriterTests {
    private let extractor = TaskExtractor(clock: FixedClock())
    private let oct2 = LocalDate.literal(2026, 10, 2)

    /// The first task of `content`, after `setting`.
    private func write(_ due: LocalDate?, in content: String, taskIndex: Int = 0) throws -> String {
        let task = try #require(extractor.extract(from: content)[taskIndex...].first, "no task in \(content.debugDescription)")
        return try DueDateWriter.setting(due, in: content, task: task)
    }

    private func line(_ input: String, _ due: LocalDate?) throws -> String {
        let out = try write(due, in: "# T\n\n\(input)\n")
        return String(out.dropFirst("# T\n\n".count).dropLast())
    }

    /// The 15-line table of the plan (plus a few edge lines): input line, new due, expected line.
    @Test func theTable() throws {
        let cases: [(String, LocalDate?, String)] = [
            ("- [ ] Read chapter 6", oct2, "- [ ] Read chapter 6 @2026-10-02"),
            ("- [ ] Read chapter 6 ^t-4f2a", oct2, "- [ ] Read chapter 6 @2026-10-02 ^t-4f2a"),
            ("- [ ] Read @2026-09-30 ^t-4f2a", oct2, "- [ ] Read @2026-10-02 ^t-4f2a"),
            ("- [ ] Ask about it @ Tue", oct2, "- [ ] Ask about it @2026-10-02"),
            ("- [x] Done thing @today ^t-1", oct2, "- [x] Done thing @2026-10-02 ^t-1"),
            ("- [ ] Essay @before-midterm  ^t-9", oct2, "- [ ] Essay @2026-10-02  ^t-9"),
            ("  * [ ] nested item @tomorrow", oct2, "  * [ ] nested item @2026-10-02"),
            ("- [ ] Email @prof about it", oct2, "- [ ] Email @prof about it @2026-10-02"),
            ("- [ ] Call @prof @next-week now", oct2, "- [ ] Call @prof @2026-10-02 now"),
            ("- [ ] Trailing spaces   ", oct2, "- [ ] Trailing spaces @2026-10-02   "),
            ("- [ ] Read @2026-09-30 ^t-4f2a", nil, "- [ ] Read ^t-4f2a"),
            ("- [ ] Read @Tue chapter 6 ^t-1", nil, "- [ ] Read chapter 6 ^t-1"),
            ("- [ ] Plain task", nil, "- [ ] Plain task"),
            ("- [ ] Přečíst kapitolu 6 🎓", oct2, "- [ ] Přečíst kapitolu 6 🎓 @2026-10-02"),
            ("- [ ] Read @2026-10-02 ^t-1", oct2, "- [ ] Read @2026-10-02 ^t-1"),
            ("- [ ] Meet at @noon", oct2, "- [ ] Meet at @noon @2026-10-02"),
            ("+ [ ] Plus marker @Fri", nil, "+ [ ] Plus marker"),
            ("- [ ] Two dates @2026-09-30 and @Tue ^t-2", oct2, "- [ ] Two dates @2026-09-30 and @2026-10-02 ^t-2"),
            ("- [ ] ^t-alone", oct2, "- [ ] ^t-alone @2026-10-02"),
        ]
        #expect(cases.count >= 15)
        for (input, due, expected) in cases {
            #expect(try line(input, due) == expected, "\(input) → \(String(describing: due?.iso))")
        }
    }

    @Test func writingTwiceAndClearingAreStable() throws {
        for input in ["- [ ] A", "- [ ] A ^t-1", "- [ ] A @Tue B ^t-1", "- [ ] A @before-exam"] {
            let once = try line(input, oct2)
            #expect(try line(once, oct2) == once, "\(input)")
            let cleared = try line(once, nil)
            #expect(try line(cleared, nil) == cleared)
            #expect(!cleared.contains("@2026"), "\(input) → \(cleared)")
        }
    }

    @Test func aResultReadsBackAsTheWantedDateWithTheSameTextAndId() throws {
        for input in ["- [ ] Read chapter 6 ^t-4f2a", "- [ ] Read @Tue chapter 6 ^t-4f2a", "- [x] Přečíst @ tomorrow  ^t-x"] {
            let out = try line(input, oct2)
            let before = try #require(extractor.extract(from: input + "\n").first)
            let after = try #require(extractor.extract(from: out + "\n").first)
            #expect(after.due == oct2 && after.dueToken == .iso(oct2))
            #expect(after.text == before.text && after.blockID == before.blockID && after.done == before.done, "\(input)")
        }
    }

    @Test func removingTheOnlyTextIsRefused() throws {
        for input in ["- [ ] @Tue", "- [ ] @Tue ^t-1"] {
            #expect(throws: MarginError.self) { _ = try line(input, nil) }
        }
    }

    @Test func everythingElseInTheFileStaysByteForByte() throws {
        let content = "\u{FEFF}---\nid: n-1\n---\r\n# Note\r\n\r\n- [ ] First @Tue ^t-1\r\n- [ ] Second ^t-2\r\n\r\n```\r\n- [ ] in code @Tue\r\n```\r\n\r\n- [x] Third   \r\nlast line without newline"
        let tasks = extractor.extract(from: content)
        #expect(tasks.map(\.text) == ["First", "Second", "Third"])
        let out = try write(oct2, in: content, taskIndex: 1)
        #expect(out == content.replacingOccurrences(of: "- [ ] Second ^t-2", with: "- [ ] Second @2026-10-02 ^t-2"))
        let cleared = try write(nil, in: content, taskIndex: 0)
        #expect(cleared == content.replacingOccurrences(of: "- [ ] First @Tue ^t-1", with: "- [ ] First ^t-1"))
        // The last line without a line ending, and a task with trailing spaces before CRLF.
        let third = try write(oct2, in: content, taskIndex: 2)
        #expect(third == content.replacingOccurrences(of: "- [x] Third   \r\n", with: "- [x] Third @2026-10-02   \r\n"))
        let tail = try write(oct2, in: "- [ ] Only", in2: ())
        #expect(tail == "- [ ] Only @2026-10-02")
    }

    @Test func aRangeThatIsNotThisFileIsRefused() throws {
        let task = try #require(extractor.extract(from: "- [ ] A long enough line for a range\n").first)
        #expect(throws: MarginError.self) { _ = try DueDateWriter.setting(oct2, in: "- [ ] B\n", task: task) }
        #expect(throws: MarginError.self) { _ = try DueDateWriter.setting(oct2, in: "- [ ] A long enough line for a rangX\n", task: task) }
    }
}

private extension DueDateWriterTests {
    func write(_ due: LocalDate?, in content: String, in2: Void) throws -> String {
        let task = try #require(TaskExtractor(clock: FixedClock()).extract(from: content).first)
        return try DueDateWriter.setting(due, in: content, task: task)
    }
}
