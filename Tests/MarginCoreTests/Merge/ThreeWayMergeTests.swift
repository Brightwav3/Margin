import Foundation
import Testing
@testable import MarginCore

/// AG-04: the line-based three-way merge.
@Suite struct ThreeWayMergeTests {
    private func merge(_ b: String, _ o: String, _ t: String) -> ThreeWayMerge.Result {
        ThreeWayMerge.merge(base: b, ours: o, theirs: t, oursLabel: "yours", theirsLabel: "disk")
    }

    private let base = "# Title\n\nalpha\nbeta\ngamma\ndelta\nepsilon\n"

    @Test func identicalSidesGiveThatText() {
        let r = merge(base, "x\n", "x\n")
        #expect(r.text == "x\n" && !r.hasConflicts)
    }

    @Test func oneSideUnchangedTakesTheOther() {
        let changed = base.replacingOccurrences(of: "beta", with: "BETA")
        #expect(merge(base, changed, base).text == changed)
        #expect(merge(base, base, changed).text == changed)
        #expect(!merge(base, changed, base).hasConflicts)
    }

    @Test func nonOverlappingEditsMergeCleanly() {
        let ours = base.replacingOccurrences(of: "alpha", with: "ALPHA")
        let theirs = base.replacingOccurrences(of: "epsilon", with: "EPSILON")
        let r = merge(base, ours, theirs)
        #expect(!r.hasConflicts)
        #expect(r.text == "# Title\n\nALPHA\nbeta\ngamma\ndelta\nEPSILON\n")
        // Symmetric.
        #expect(merge(base, theirs, ours).text == r.text)
    }

    @Test func insertionsAndDeletionsInDifferentPlacesMerge() {
        let ours = "# Title\n\nalpha\nnew line\nbeta\ngamma\ndelta\nepsilon\n"
        let theirs = "# Title\n\nalpha\nbeta\ngamma\nepsilon\n"          // deleted delta
        let r = merge(base, ours, theirs)
        #expect(!r.hasConflicts)
        #expect(r.text == "# Title\n\nalpha\nnew line\nbeta\ngamma\nepsilon\n")
    }

    @Test func theSameChangeOnBothSidesIsTakenOnce() {
        let both = base.replacingOccurrences(of: "gamma", with: "GAMMA")
        let ours = both.replacingOccurrences(of: "alpha", with: "ALPHA")
        let theirs = both.replacingOccurrences(of: "epsilon", with: "EPSILON")
        let r = merge(base, ours, theirs)
        #expect(!r.hasConflicts)
        #expect(r.text == "# Title\n\nALPHA\nbeta\nGAMMA\ndelta\nEPSILON\n")
    }

    @Test func overlappingEditsConflictWithMarkersKeepingBothSides() {
        let ours = base.replacingOccurrences(of: "gamma", with: "mine")
        let theirs = base.replacingOccurrences(of: "gamma", with: "theirs")
        let r = merge(base, ours, theirs)
        #expect(r.conflictCount == 1)
        #expect(r.text == "# Title\n\nalpha\nbeta\n<<<<<<< yours\nmine\n=======\ntheirs\n>>>>>>> disk\ndelta\nepsilon\n")
    }

    @Test func insertionsAtTheSamePlaceConflict() {
        let ours = base + "mine\n"
        let theirs = base + "theirs\n"
        let r = merge(base, ours, theirs)
        #expect(r.conflictCount == 1)
        #expect(r.text.contains("mine\n=======\ntheirs\n"))
    }

    @Test func touchingChangesConflict() {
        // Adjacent lines edited by different sides: no unchanged line between them.
        let ours = base.replacingOccurrences(of: "beta", with: "B1")
        let theirs = base.replacingOccurrences(of: "gamma", with: "G1")
        #expect(merge(base, ours, theirs).conflictCount == 1)
    }

    @Test func editVersusDeletionConflicts() {
        let ours = base.replacingOccurrences(of: "gamma\n", with: "GAMMA\n")
        let theirs = base.replacingOccurrences(of: "gamma\n", with: "")
        let r = merge(base, ours, theirs)
        #expect(r.conflictCount == 1)
        #expect(r.text.contains("GAMMA\n=======\n>>>>>>> disk\n"))
    }

    @Test func twoSeparateConflictsAreCounted() {
        let ours = base.replacingOccurrences(of: "alpha", with: "A1").replacingOccurrences(of: "epsilon", with: "E1")
        let theirs = base.replacingOccurrences(of: "alpha", with: "A2").replacingOccurrences(of: "epsilon", with: "E2")
        let r = merge(base, ours, theirs)
        #expect(r.conflictCount == 2)
    }

    @Test func aMissingFinalNewlineStillGetsCleanMarkers() {
        let r = merge("a\nb", "a\nours", "a\ntheirs")
        #expect(r.text == "a\n<<<<<<< yours\nours\n=======\ntheirs\n>>>>>>> disk\n")
    }

    @Test func crlfLineEndingsSurviveByteForByte() {
        let b = "one\r\ntwo\r\nthree\r\nfour\r\nfive\r\n"
        let ours = "ONE\r\ntwo\r\nthree\r\nfour\r\nfive\r\n"
        let theirs = "one\r\ntwo\r\nthree\r\nfour\r\nFIVE\r\n"
        let r = merge(b, ours, theirs)
        #expect(!r.hasConflicts)
        #expect(Array(r.text.utf8) == Array("ONE\r\ntwo\r\nthree\r\nfour\r\nFIVE\r\n".utf8))
    }

    @Test func aLineEndingChangeIsAChangeNotNoise() {
        let b = "a\nb\nc\nd\ne\n"
        let ours = "a\r\nb\nc\nd\ne\n"          // only the ending of line 1 differs
        let theirs = "a\nb\nc\nd\nE\n"
        let r = merge(b, ours, theirs)
        #expect(!r.hasConflicts)
        #expect(Array(r.text.utf8) == Array("a\r\nb\nc\nd\nE\n".utf8))
    }

    @Test func unicodeNormalizationIsCompared_byBytes() {
        let precomposed = "caf\u{E9}\n"                 // é as one scalar
        let decomposed = "cafe\u{301}\n"               // e + combining acute; == precomposed in Swift
        #expect(precomposed == decomposed)              // documents why bytes must be compared
        let b = "x\n\(precomposed)y\nz\nw\n"
        let ours = "x\n\(decomposed)y\nz\nw\n"         // a byte-level change
        let theirs = "x\n\(precomposed)y\nz\nW\n"
        let r = merge(b, ours, theirs)
        #expect(!r.hasConflicts)
        #expect(Array(r.text.utf8) == Array("x\n\(decomposed)y\nz\nW\n".utf8), "the normalization change was dropped")
        // Same when the only difference is normalization: the change is not lost.
        #expect(Array(merge(b, ours, b).text.utf8) == Array(ours.utf8))
    }

    @Test func emptyAndDegenerateInputs() {
        #expect(merge("", "", "").text == "")
        #expect(merge("", "a\n", "").text == "a\n")
        #expect(merge("", "", "b\n").text == "b\n")
        #expect(merge("", "a\n", "b\n").conflictCount == 1)
        #expect(merge("a\n", "", "").text == "")
        #expect(merge("a\n", "", "a\nb\n").hasConflicts)      // one side deleted everything, the other appended
    }

    @Test func tooDifferentTextsGiveOneWholeFileConflictAndLoseNothing() {
        let a = (0..<3_000).map { "left \($0)\n" }.joined()
        let b = (0..<3_000).map { "right \($0)\n" }.joined()
        let base = (0..<3_000).map { "base \($0)\n" }.joined()
        let r = merge(base, a, b)
        #expect(r.gaveUp && r.conflictCount == 1)
        #expect(r.text.contains("left 0\n") && r.text.contains("left 2999\n"))
        #expect(r.text.contains("right 0\n") && r.text.contains("right 2999\n"))
        #expect(r.text.hasPrefix("<<<<<<< yours\n"))
    }

    @Test func largeFilesWithSmallEditsMergeQuickly() {
        let lines = (0..<20_000).map { "line \($0)\n" }
        var o = lines, t = lines
        o[100] = "ours 100\n"; o.insert("inserted\n", at: 15_000)
        t[19_000] = "theirs 19000\n"; t.remove(at: 5_000)
        let r = merge(lines.joined(), o.joined(), t.joined())
        #expect(!r.hasConflicts)
        // Expected: apply both edits to the base (theirs' deletion first, so ours' index shifts by one).
        var expected = lines
        expected[100] = "ours 100\n"
        expected[19_000] = "theirs 19000\n"
        expected.insert("inserted\n", at: 15_000)
        expected.remove(at: 5_000)
        #expect(r.text == expected.joined())
    }

    // MARK: Properties (seeded)

    private struct Case { var base: [String]; var ours: [String]; var theirs: [String] }

    private func randomLines(_ rng: inout SplitMix64, count: Int, tag: String) -> [String] {
        (0..<count).map { "\(tag)\($0) \(rng.next() % 5)\n" }
    }

    @Test func cleanMergeIsSymmetricAndConflictFreeWhenOneSideIsBase() {
        var rng = SplitMix64(seed: 0xA604)
        for _ in 0..<300 {
            let base = randomLines(&rng, count: Int(rng.next() % 30), tag: "b")
            func edit(_ lines: [String], tag: String) -> [String] {
                var l = lines
                for _ in 0..<Int(rng.next() % 4) {
                    switch rng.next() % 3 {
                    case 0 where !l.isEmpty: l[Int(rng.next() % UInt64(l.count))] = "\(tag)-edit \(rng.next() % 1000)\n"
                    case 1: l.insert("\(tag)-ins \(rng.next() % 1000)\n", at: l.isEmpty ? 0 : Int(rng.next() % UInt64(l.count + 1)))
                    case 2 where !l.isEmpty: l.remove(at: Int(rng.next() % UInt64(l.count)))
                    default: break
                    }
                }
                return l
            }
            let ours = edit(base, tag: "o"), theirs = edit(base, tag: "t")
            let b = base.joined(), o = ours.joined(), t = theirs.joined()

            let r1 = merge(b, o, b), r2 = merge(b, b, t), r3 = merge(b, o, o)
            #expect(!r1.hasConflicts && r1.text == o)
            #expect(!r2.hasConflicts && r2.text == t)
            #expect(!r3.hasConflicts && r3.text == o)

            let ab = merge(b, o, t), ba = merge(b, t, o)
            #expect(ab.hasConflicts == ba.hasConflicts)
            if !ab.hasConflicts { #expect(ab.text == ba.text, "merge is not symmetric") }
            // Nothing is lost: every line either side added survives (as a clean line or inside markers).
            for line in Set(ours).subtracting(base).union(Set(theirs).subtracting(base)) {
                #expect(ab.text.contains(line), "lost \(line.debugDescription)")
            }
        }
    }

    @Test func editsInSeparatedRegionsAlwaysMergeToTheExpectedText() {
        var rng = SplitMix64(seed: 0xB0B)
        for _ in 0..<300 {
            let n = 12 + Int(rng.next() % 30)
            let base = (0..<n).map { "line \($0)\n" }
            // Ours edits inside [0, cut-2], theirs inside [cut+1, n-1]: at least two untouched lines between.
            let cut = 4 + Int(rng.next() % UInt64(n - 8))
            var ours = base, theirs = base
            var expected = base
            for i in 0..<(cut - 1) where rng.next() % 3 == 0 { ours[i] = "OURS \(i)\n"; expected[i] = "OURS \(i)\n" }
            for i in (cut + 2)..<n where rng.next() % 3 == 0 { theirs[i] = "THEIRS \(i)\n"; expected[i] = "THEIRS \(i)\n" }
            let r = merge(base.joined(), ours.joined(), theirs.joined())
            #expect(!r.hasConflicts)
            #expect(r.text == expected.joined())
        }
    }

    /// The optimization (skip the lines all three texts share at both ends) must not change any result.
    /// Lines are unique here: with repeated lines several alignments are equally good and the two
    /// variants may legitimately pick different ones (both are valid merges).
    @Test func trimmingTheCommonEdgesGivesTheSameResultAsDiffingEverything() {
        var rng = SplitMix64(seed: 0xED6E5)
        func pick(_ n: Int) -> Int { Int(rng.next() % UInt64(max(n, 1))) }
        var fresh = 0
        for round in 0..<800 {
            func line() -> String { fresh += 1; return round % 7 == 0 ? "é\(fresh)\r\n" : "x\(fresh)\n" }
            let base = (0..<pick(16)).map { _ in line() }
            func edit(_ l: [String]) -> [String] {
                var l = l
                for _ in 0..<pick(4) {
                    switch pick(3) {
                    case 0 where !l.isEmpty: l[pick(l.count)] = line()
                    case 1: l.insert(line(), at: pick(l.count + 1))
                    case 2 where !l.isEmpty: l.remove(at: pick(l.count))
                    default: break
                    }
                }
                return l
            }
            var ours = edit(base), theirs = edit(base)
            if round % 5 == 0, !ours.isEmpty, !theirs.isEmpty { theirs[0] = ours[0] }            // some identical changes
            if round % 11 == 0 { ours = ours.map { $0.hasSuffix("\n") ? $0 : $0 + "\n" } ; if let last = ours.last { ours[ours.count - 1] = String(last.dropLast()) } }   // no final newline
            let b = base.joined(), o = ours.joined(), t = theirs.joined()
            let fast = ThreeWayMerge.merge(base: b, ours: o, theirs: t, oursLabel: "o", theirsLabel: "t", trimEdges: true)
            let full = ThreeWayMerge.merge(base: b, ours: o, theirs: t, oursLabel: "o", theirsLabel: "t", trimEdges: false)
            #expect(Array(fast.text.utf8) == Array(full.text.utf8), "base \(b.debugDescription) ours \(o.debugDescription) theirs \(t.debugDescription)")
            #expect(fast.conflictCount == full.conflictCount)
        }
    }
}
