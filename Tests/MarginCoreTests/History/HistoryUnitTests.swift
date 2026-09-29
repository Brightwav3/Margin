import Foundation
import Testing
@testable import MarginCore

private struct HistoryTestRNG {
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

@Suite struct LineDiffTests {
    private func rebuild(_ d: NoteDiff) -> (old: [String], new: [String]) {
        (d.lines.filter { $0.kind != .added }.map(\.text), d.lines.filter { $0.kind != .removed }.map(\.text))
    }

    @Test func identicalAndEmptyTexts() {
        #expect(LineDiff.diff(old: "", new: "").lines.isEmpty)
        let same = LineDiff.diff(old: "a\nb\n", new: "a\nb\n")
        #expect(same.isIdentical && same.lines.count == 2 && same.lines[1].oldLine == 2 && same.lines[1].newLine == 2)
        let added = LineDiff.diff(old: "", new: "x\ny")
        #expect(added.lines.map(\.kind) == [.added, .added] && added.lines.map(\.newLine) == [1, 2] && added.lines[0].oldLine == nil)
        #expect(LineDiff.diff(old: "x\n", new: "").lines.map(\.kind) == [.removed])
    }

    @Test func finalLineBreakIsNotALine() {
        #expect(LineDiff.lines(of: "a\n") == ["a"] && LineDiff.lines(of: "a\n\n") == ["a", ""] && LineDiff.lines(of: "a\nb") == ["a", "b"])
        #expect(LineDiff.lines(of: "\n") == [""])
    }

    @Test func lineNumbersPointAtBothTexts() {
        let d = LineDiff.diff(old: "a\nb\nc\nd\n", new: "a\nc\nX\nd\n")
        #expect(d.lines.map(\.kind) == [.equal, .removed, .equal, .added, .equal])
        #expect(d.lines.map(\.oldLine) == [1, 2, 3, nil, 4] && d.lines.map(\.newLine) == [1, nil, 2, 3, 4])
    }

    @Test func aLineBreakStyleChangeShows() {
        let d = LineDiff.diff(old: "a\r\nb\r\n", new: "a\nb\n")
        #expect(d.removedCount == 2 && d.addedCount == 2)
    }

    @Test func randomEditsRebuildBothTextsAndAreMinimal() {
        var rng = HistoryTestRNG(state: 42)
        for _ in 0..<300 {
            let old = (0..<rng.below(25)).map { _ in "l\(rng.below(6))" }
            var new = old
            for _ in 0..<rng.below(6) {
                switch rng.below(3) {
                case 0 where !new.isEmpty: new.remove(at: rng.below(new.count))
                case 1: new.insert("n\(rng.below(4))", at: rng.below(new.count + 1))
                default: if !new.isEmpty { new[rng.below(new.count)] = "m\(rng.below(3))" }
                }
            }
            let d = LineDiff.diff(oldLines: old, newLines: new)
            let (o, n) = rebuild(d)
            #expect(o == old && n == new)
            // Never worse than the edits that were made (each edit costs at most 2 lines).
            #expect(d.addedCount + d.removedCount <= 12)
        }
    }

    @Test func hugeMiddleFallsBackToReplaceAll() {
        let old = (0..<2500).map { "a\($0)" }, new = (0..<2500).map { "b\($0)" }
        #expect(old.count * new.count > LineDiff.maxCells)
        let d = LineDiff.diff(oldLines: old, newLines: new)
        #expect(d.removedCount == 2500 && d.addedCount == 2500)
        let (o, n) = rebuild(d)
        #expect(o == old && n == new)
    }
}

@Suite struct SnapshotFormatTests {
    @Test func rawRoundTripKeepsAnyText() throws {
        for text in ["", "plain", "Příliš žluťoučký kůň\n– ünï 🎓\r\n", String(repeating: "x", count: 100_000)] {
            let data = SnapshotFormat.encode(text, codec: RawCodec())
            #expect(SnapshotFormat.size(of: data) == text.utf8.count)
            #expect(try SnapshotFormat.decode(data) == text)
        }
    }

    @Test func thePreferredCodecRoundTripsToo() throws {
        let text = String(repeating: "the cell membrane ", count: 500)
        let data = SnapshotFormat.encode(text)
        #expect(try SnapshotFormat.decode(data) == text)
        #expect(data.count < text.utf8.count + 10)
        #expect(try SnapshotFormat.decode(SnapshotFormat.encode("")) == "")
    }

    @Test func damagedSnapshotsAreIoErrorsNotCrashes() {
        func code(_ d: Data) -> String? { do { _ = try SnapshotFormat.decode(d); return nil } catch let e as MarginError { return e.code } catch { return "other" } }
        let good = SnapshotFormat.encode("hello", codec: RawCodec())
        #expect(code(Data()) == "io" && code(Data("nope".utf8)) == "io")
        var wrongLength = good; wrongLength.removeLast()
        #expect(code(wrongLength) == "io")
        var unknownCodec = good; unknownCodec[4] = 200
        #expect(code(unknownCodec) == "io")
        var notUTF8 = SnapshotFormat.encode("abc", codec: RawCodec()); notUTF8[9] = 0xFF
        #expect(code(notUTF8) == "io")
        #expect(SnapshotFormat.size(of: Data("x".utf8)) == nil)
    }

    @Test func zlibFramingMatchesRFC1950() throws {
        #expect(ZlibFraming.adler32(Data("Wikipedia".utf8)) == 0x11E6_0398 && ZlibFraming.adler32(Data()) == 1)
        // What Python's zlib.compress(b"hello") produces, so the container is the standard one.
        let stream = Data([0x78, 0x9C, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00, 0x06, 0x2C, 0x02, 0x15])
        let (deflated, adler) = try ZlibFraming.unwrap(stream)
        #expect(deflated == Data([0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00]) && adler == ZlibFraming.adler32(Data("hello".utf8)))
        #expect(ZlibFraming.wrap(deflated: deflated, original: Data("hello".utf8)) == stream)
        #expect(throws: MarginError.self) { try ZlibFraming.unwrap(Data([0x00, 0x01, 2, 3, 4, 5, 6])) }
    }

    @Test func folderNamesAreSafeAndDistinct() {
        let ids = ["bio/lecture-9", "bio_lecture-9", "n_ab12", ".hidden", "a b", "%2F", "č", ""]
        let names = ids.map(VaultHistoryStorage.folderName(for:))
        #expect(Set(names).count == ids.count)
        #expect(names.allSatisfy { !$0.contains("/") && !$0.hasPrefix(".") && !$0.isEmpty })
        #expect(VaultHistoryStorage.folderName(for: "n_ab12") == "n_ab12" && VaultHistoryStorage.folderName(for: "bio/lecture-9") == "bio%2Flecture-9")
    }
}
