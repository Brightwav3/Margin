import Foundation
import Testing
@testable import MarginCore

@Suite struct VaultPathTests {
    @Test func normalizes() throws {
        #expect(try VaultPath("a//b/./c.md/").rawValue == "a/b/c.md")
        #expect(try VaultPath("./Fall 2026/Cell Biology/Lecture 8 — Cell membrane.md").components.count == 3)
        #expect(try VaultPath("a/b.md").parent?.rawValue == "a")
        #expect(try VaultPath("b.md").parent == nil)
        #expect(try VaultPath("x/Note.MD").pathExtension == "md")
        #expect(try VaultPath("x/.hidden").pathExtension == "")
    }

    @Test func rejectsUnsafePaths() {
        let bad = ["", "/", ".", "./", "/etc/passwd", "..", "../x.md", "a/../b.md", "a/..", "a/b/../../../c",
                   "a\u{0}b.md", "a/\u{0}", "line\nbreak.md", "tab\t.md", "del\u{7f}.md",
                   String(repeating: "x", count: 256)]
        for s in bad {
            #expect(throws: MarginError.self, "should reject \(s.debugDescription)") { try VaultPath(s) }
        }
        #expect(throws: MarginError.self) { try VaultPath(components: ["a", "b/c"]) }
        #expect(throws: MarginError.self) { try VaultPath(components: ["a", ".."]) }
        #expect(throws: MarginError.self) { try VaultPath(components: []) }
        // Dots inside a name are fine.
        #expect(throws: Never.self) { try VaultPath("a..b/..c/d..md") }
    }

    @Test func codableRejectsInvalid() throws {
        let p = try VaultPath("a/b.md")
        #expect(try JSONDecoder().decode([VaultPath].self, from: JSONEncoder().encode([p])) == [p])
        #expect(throws: (any Error).self) { try JSONDecoder().decode([VaultPath].self, from: Data("[\"../x\"]".utf8)) }
    }

    @Test func containmentAndFlags() throws {
        let margin = try VaultPath(".margin/trash/x")
        #expect(margin.isInternal && margin.isHidden)
        let dotMargin = try VaultPath(".margin"), a = try VaultPath("a"), ab = try VaultPath("a/b")
        #expect(margin.isInside(dotMargin))
        #expect(!(try VaultPath(".marginal/x")).isInside(dotMargin))
        #expect(ab.isInside(ab))
        #expect(!a.isInside(ab))
        #expect(try VaultPath("a/b").appending("c.md").rawValue == "a/b/c.md")
        #expect(throws: MarginError.self) { try VaultPath("a").appending("..") }
        #expect(throws: MarginError.self) { try VaultPath("a").appending(path: "../x") }
    }

    @Test func filenameFromTitle() throws {
        #expect(VaultPath.filename(fromTitle: "Lecture 8 — Cell membrane") == "Lecture 8 — Cell membrane")
        #expect(VaultPath.filename(fromTitle: "a/b:c\\d") == "a-b-c-d")
        #expect(VaultPath.filename(fromTitle: "  Spaces  ") == "Spaces")
        #expect(VaultPath.filename(fromTitle: "..hidden") == "hidden")
        #expect(VaultPath.filename(fromTitle: "") == "Untitled")
        #expect(VaultPath.filename(fromTitle: "///") == "---")
        #expect(VaultPath.filename(fromTitle: "...") == "Untitled")
        #expect(VaultPath.filename(fromTitle: "one\ntwo\u{0}") == "one two")
        // NFD input becomes NFC so the name is stable across platforms.
        #expect(VaultPath.filename(fromTitle: "Cafe\u{301}") == "Caf\u{e9}")
        let long = VaultPath.filename(fromTitle: String(repeating: "ž", count: 300))
        #expect(long.utf8.count + 3 <= 255)
        #expect(try VaultPath.note(titled: "Glossary: terms", in: VaultPath("Fall/Bio")).rawValue == "Fall/Bio/Glossary- terms.md")
        #expect(try VaultPath.note(titled: "../../evil").rawValue == "-..-evil.md")
    }

    @Test func derivedNamesAreAlwaysValidPaths() throws {
        var rng = SplitMix64(seed: 42)
        let alphabet = Array("ab /:\\.\u{0}\n—ž..é\u{301}\t").map(String.init)
        for _ in 0..<2000 {
            let title = (0..<Int(rng.next() % 40)).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] }.joined()
            let path = try VaultPath.note(titled: title)
            #expect(path.components.count == 1, "title \(title.debugDescription)")
            #expect(!path.isHidden)
        }
    }
}

/// Deterministic RNG for tests.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
