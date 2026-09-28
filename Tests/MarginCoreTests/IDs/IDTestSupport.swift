import Foundation
@testable import MarginCore

/// Seeded, reproducible id source (wraps the shared test `SplitMix64`).
struct SeededIDSource: IDRandomSource {
    var rng: SplitMix64
    init(seed: UInt64) { rng = SplitMix64(seed: seed) }
    mutating func next() -> UInt64 { rng.next() }
}

/// A source that always returns the same value (degenerate on purpose).
struct ConstantIDSource: IDRandomSource {
    var value: UInt64
    mutating func next() -> UInt64 { value }
}

/// A source that replays a fixed list, then repeats the last value.
struct ScriptedIDSource: IDRandomSource {
    var values: [UInt64]
    mutating func next() -> UInt64 {
        values.count > 1 ? values.removeFirst() : (values.first ?? 0)
    }
}

func makeGenerator(_ seed: UInt64 = 1) -> StableIDGenerator {
    StableIDGenerator(source: SeededIDSource(seed: seed))
}

/// Replaces generated ids so expected texts can be written literally: `^t-4f2a` -> `^T`,
/// `id: n-9c1e` -> `id: N`.
func masked(_ text: String) -> String {
    text.replacing(#/\^t-[0-9a-z]{4,6}/#, with: "^T")
        .replacing(#/id: n-[0-9a-z]{4,6}/#, with: "id: N")
}

/// Normal form for "everything else is identical" checks: CRLF -> LF, the generated `^t-…` at the
/// end of a line removed, trailing spaces and tabs trimmed. (Exact whitespace is asserted by the
/// explicit tests; the count of CR bytes is compared separately.)
func stripInserted(_ text: String) -> String {
    let lf = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
    return lf.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        var l = String(line).replacing(#/\^t-[0-9a-z]{4,6}[ \t]*$/#, with: "")
        while let last = l.last, last == " " || last == "\t" { l.removeLast() }
        return l
    }.joined(separator: "\n")
}

func carriageReturns(_ text: String) -> Int { text.utf8.filter { $0 == 0x0D }.count }

func assign(_ text: String, seed: UInt64 = 1, existing: Set<String> = []) -> IDAssignmentResult {
    var g = makeGenerator(seed)
    return IDAssigner().assign(to: text, generator: &g, existing: existing)
}
