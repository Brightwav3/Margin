import Foundation
import Testing
@testable import MarginCore

@Suite struct TaskToggleTests {
    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    @Test func flipsOpenToDoneAndBack() throws {
        let text = "# T\n\n- [ ] one @fri ^t-1\n- [x] two\n"
        let once = try TaskToggle.toggled(text, line: 3)
        #expect(once == "# T\n\n- [x] one @fri ^t-1\n- [x] two\n")
        #expect(try TaskToggle.toggled(once, line: 4) == "# T\n\n- [x] one @fri ^t-1\n- [ ] two\n")
        #expect(try TaskToggle.toggled(once, line: 3) == text)
    }

    @Test func capitalXAndOtherMarkersAndIndentation() throws {
        let text = "* [X] star\n+ [ ] plus\n\t- [ ] tab\n    \n  - [x] nested\n"
        #expect(try TaskToggle.toggled(text, line: 1) == "* [ ] star\n+ [ ] plus\n\t- [ ] tab\n    \n  - [x] nested\n")
        #expect(try TaskToggle.toggled(text, line: 2) == "* [X] star\n+ [x] plus\n\t- [ ] tab\n    \n  - [x] nested\n")
        #expect(try TaskToggle.toggled(text, line: 3).contains("\t- [x] tab"))
        #expect(try TaskToggle.toggled(text, line: 5).contains("  - [ ] nested"))
    }

    @Test func everythingElseStaysByteIdentical() throws {
        // CRLF, a BOM, non-ASCII text, trailing spaces, no final newline.
        let text = "\u{FEFF}- [ ] První úkol — čeština  \r\nvolný řádek\r\n- [x] Druhý 📅\r\n- [ ] poslední"
        for line in [1, 3, 4] {
            let out = try TaskToggle.toggled(text, line: line)
            let (a, b) = (Array(text.utf8), Array(out.utf8))
            #expect(a.count == b.count)
            let diffs = zip(a, b).enumerated().filter { $0.element.0 != $0.element.1 }
            #expect(diffs.count == 1, "line \(line)")
            #expect(try TaskToggle.toggled(out, line: line) == text)
        }
    }

    @Test func settingIsIdempotent() throws {
        let text = "- [ ] a\n- [x] b\n"
        #expect(try TaskToggle.setting(text, line: 1, done: false) == text)
        #expect(try TaskToggle.setting(text, line: 1, done: true) == "- [x] a\n- [x] b\n")
        #expect(try TaskToggle.setting(text, line: 2, done: true) == text)
    }

    @Test func linesThatAreNotTasksAreNotFound() {
        let text = "# T\n\n- plain item\n```\n- [ ] in code\n```\n\n    - [ ] indented code\n\n| a | [ ] |\nprose - [ ] mid\n- [ ]\n"
        for line in [0, 1, 3, 5, 8, 10, 11, 12, 99] {
            do {
                _ = try TaskToggle.toggled(text, line: line)
                Issue.record("line \(line) must not be a task")
            } catch let error as MarginError {
                if case .notFound = error {} else { Issue.record("line \(line): \(error)") }
            } catch { Issue.record("\(error)") }
        }
    }

    /// Round trip over random documents: toggling every task twice restores the text, a single toggle
    /// changes exactly one byte and no other task.
    @Test func roundTripOverRandomDocuments() throws {
        var rng = SplitMix64(state: 11)
        let pieces = [
            "- [ ] open", "- [x] done", "  - [ ] nested", "    - [x] deep", "* [ ] star", "\t- [ ] tab @2026-10-01 ^t-9",
            "```", "~~~", "prose [ ] here", "", "# Heading", "- item", "1. [ ] ordered", "text [[link]]",
        ]
        var togglings = 0
        for _ in 0..<300 {
            let eol = rng.below(2) == 0 ? "\n" : "\r\n"
            let text = (0..<(5 + rng.below(30))).map { _ in pieces[rng.below(pieces.count)] }.joined(separator: eol)
            let tasks = MarkdownScanner().scan(text).tasks
            for task in tasks {
                let once = try TaskToggle.toggled(text, line: task.line)
                let (a, b) = (Array(text.utf8), Array(once.utf8))
                #expect(a.count == b.count && zip(a, b).filter { $0 != $1 }.count == 1)
                let after = MarkdownScanner().scan(once).tasks
                #expect(after.count == tasks.count)
                for (x, y) in zip(tasks, after) { #expect((x.done != y.done) == (x.line == task.line)) }
                #expect(try TaskToggle.toggled(once, line: task.line) == text)
                togglings += 1
            }
        }
        #expect(togglings > 500)
    }
}
