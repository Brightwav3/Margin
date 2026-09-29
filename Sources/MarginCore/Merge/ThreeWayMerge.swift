import Foundation

/// Line-based three-way merge (diff3) of text, used when two writers changed the same note.
///
/// `merge(base:ours:theirs:)` takes the text both writers started from (`base`) and the two
/// changed versions. Lines the writers left alone stay; a change made by only one side is taken;
/// identical changes are taken once; a region changed differently on both sides is a conflict.
/// Changes that touch (no unchanged line between them) count as overlapping, so a clean result
/// means the two edits really were independent.
///
/// Guarantees:
/// - **Bytes, not characters:** lines are compared by their UTF-8 bytes, never by Swift's
///   canonical string equality, so a text that differs only in Unicode normalization or line
///   endings is a change, not "the same". Line terminators (`\n`, `\r\n`) stay part of their line.
/// - **Nothing is dropped:** on a conflict both versions of the region are kept between markers.
/// - **Deterministic:** the same three texts always give the same result. When lines repeat, several
///   alignments of two texts are equally good; one is chosen (the same one every time), so which of
///   two equally valid merges you get is unspecified, but none loses text.
/// - **Bounded cost:** diffs of extremely different texts are refused (`Result.gaveUp`) and yield
///   one conflict over the whole text instead of exhausting memory.
public enum ThreeWayMerge {
    public struct Result: Sendable, Hashable {
        /// The merged text. With conflicts it contains marker lines
        /// (`<<<<<<<`, `=======`, `>>>>>>>`), otherwise it is the clean merge.
        public var text: String
        /// Number of conflicting regions.
        public var conflictCount: Int
        /// `true` when the texts were too different to diff and the whole text is one conflict.
        public var gaveUp: Bool

        public var hasConflicts: Bool { conflictCount > 0 }
    }

    /// The largest edit distance (`D` of Myers' algorithm) the merge is willing to compute.
    /// Memory is roughly `D²` integers.
    static let maxEditDistance = 2_000

    /// Merges `ours` and `theirs`, both derived from `base`.
    ///
    /// - Parameters:
    ///   - oursLabel/theirsLabel: text after `<<<<<<<` and `>>>>>>>` in conflict markers.
    public static func merge(base: String, ours: String, theirs: String,
                             oursLabel: String = "ours", theirsLabel: String = "theirs") -> Result {
        merge(base: base, ours: ours, theirs: theirs, oursLabel: oursLabel, theirsLabel: theirsLabel, trimEdges: true)
    }

    /// `trimEdges: false` diffs the whole texts (the reference the optimization is tested against).
    static func merge(base: String, ours: String, theirs: String, oursLabel: String, theirsLabel: String,
                      trimEdges: Bool) -> Result {
        let b = Array(base.utf8), o = Array(ours.utf8), t = Array(theirs.utf8)
        // Fast paths, byte-exact.
        if o == t { return Result(text: ours, conflictCount: 0, gaveUp: false) }
        if b == o { return Result(text: theirs, conflictCount: 0, gaveUp: false) }
        if b == t { return Result(text: ours, conflictCount: 0, gaveUp: false) }

        // Lines all three texts share at the start and at the end are stable by definition; only
        // the middle needs diffing. (Byte-exact, aligned to line starts in all three texts.)
        let (prefix, suffix) = trimEdges ? commonEdges(b, o, t) : (0, 0)
        let bm = Array(b[prefix..<(b.count - suffix)]), om = Array(o[prefix..<(o.count - suffix)]), tm = Array(t[prefix..<(t.count - suffix)])
        let head = Array(b[..<prefix]), tail = Array(b[(b.count - suffix)...])

        let baseLines = splitLines(bm), oursLines = splitLines(om), theirsLines = splitLines(tm)
        // Intern lines to integers so comparisons are cheap and byte-exact.
        var table = LineTable()
        let bi = baseLines.map { table.id(of: $0) }, oi = oursLines.map { table.id(of: $0) }, ti = theirsLines.map { table.id(of: $0) }

        guard let matchO = matching(bi, oi), let matchT = matching(bi, ti) else {
            let text = conflictBlock(ours: o[...], theirs: t[...], oursLabel: oursLabel, theirsLabel: theirsLabel)
            return Result(text: String(decoding: text, as: UTF8.self), conflictCount: 1, gaveUp: true)
        }

        var out: [UInt8] = head
        out.reserveCapacity(max(o.count, t.count) + 64)
        var conflicts = 0

        func emit(_ lines: [ArraySlice<UInt8>], _ range: Range<Int>) {
            for i in range { out.append(contentsOf: lines[i]) }
        }
        func chunk(_ br: Range<Int>, _ or: Range<Int>, _ tr: Range<Int>) {
            if br.isEmpty && or.isEmpty && tr.isEmpty { return }
            let oursSame = bi[br] == oi[or]
            let theirsSame = bi[br] == ti[tr]
            if oursSame { emit(theirsLines, tr); return }
            if theirsSame { emit(oursLines, or); return }
            if oi[or] == ti[tr] { emit(oursLines, or); return }
            conflicts += 1
            var oursBytes: [UInt8] = [], theirsBytes: [UInt8] = []
            for i in or { oursBytes.append(contentsOf: oursLines[i]) }
            for i in tr { theirsBytes.append(contentsOf: theirsLines[i]) }
            out.append(contentsOf: conflictBlock(ours: oursBytes[...], theirs: theirsBytes[...],
                                                 oursLabel: oursLabel, theirsLabel: theirsLabel))
        }

        var nb = 0, no = 0, nt = 0
        for i in 0..<bi.count where matchO[i] >= 0 && matchT[i] >= 0 {
            chunk(nb..<i, no..<matchO[i], nt..<matchT[i])
            emit(baseLines, i..<(i + 1))
            nb = i + 1; no = matchO[i] + 1; nt = matchT[i] + 1
        }
        chunk(nb..<bi.count, no..<oi.count, nt..<ti.count)
        out.append(contentsOf: tail)
        return Result(text: String(decoding: out, as: UTF8.self), conflictCount: conflicts, gaveUp: false)
    }

    // MARK: Common edges

    /// Lengths in bytes of the prefix and the suffix that base, ours and theirs share, both made of
    /// whole lines and not overlapping in any of the three texts.
    static func commonEdges(_ b: [UInt8], _ o: [UInt8], _ t: [UInt8]) -> (prefix: Int, suffix: Int) {
        let shortest = min(b.count, o.count, t.count)
        return b.withUnsafeBufferPointer { bp in o.withUnsafeBufferPointer { op in t.withUnsafeBufferPointer { tp in
            var p = 0
            while p < shortest, bp[p] == op[p], bp[p] == tp[p] { p += 1 }
            // Back up to just after a newline: the prefix must consist of whole lines.
            while p > 0, bp[p - 1] != 0x0A { p -= 1 }
            var s = 0
            while s < shortest - p, bp[b.count - 1 - s] == op[o.count - 1 - s], bp[b.count - 1 - s] == tp[t.count - 1 - s] { s += 1 }
            // The suffix must start at a line start in all three texts (or at the end of the prefix).
            func startsLine(_ buf: UnsafeBufferPointer<UInt8>, _ count: Int, _ s: Int) -> Bool {
                let start = count - s
                return start == p || buf[start - 1] == 0x0A
            }
            while s > 0, !(startsLine(bp, b.count, s) && startsLine(op, o.count, s) && startsLine(tp, t.count, s)) { s -= 1 }
            return (p, s)
        } } }
    }

    /// Interns lines: equal byte sequences get the same integer. Uses a cheap FNV-1a hash and
    /// confirms every hit byte by byte, so a collision can never merge two different lines.
    private struct LineTable {
        private var buckets: [UInt64: [(line: ArraySlice<UInt8>, id: Int)]] = [:]
        private var next = 0

        mutating func id(of line: ArraySlice<UInt8>) -> Int {
            var h: UInt64 = 0xcbf29ce484222325
            line.withUnsafeBufferPointer { p in for byte in p { h = (h ^ UInt64(byte)) &* 0x100000001b3 } }
            if let candidates = buckets[h], let hit = candidates.first(where: { $0.line.elementsEqual(line) }) { return hit.id }
            let id = next
            next += 1
            buckets[h, default: []].append((line, id))
            return id
        }
    }

    // MARK: Conflict markers

    private static func conflictBlock(ours: ArraySlice<UInt8>, theirs: ArraySlice<UInt8>,
                                      oursLabel: String, theirsLabel: String) -> [UInt8] {
        var out = Array("<<<<<<< \(oursLabel)\n".utf8)
        out.append(contentsOf: ours)
        if let last = ours.last, last != 0x0A { out.append(0x0A) }
        out.append(contentsOf: Array("=======\n".utf8))
        out.append(contentsOf: theirs)
        if let last = theirs.last, last != 0x0A { out.append(0x0A) }
        out.append(contentsOf: Array(">>>>>>> \(theirsLabel)\n".utf8))
        return out
    }

    // MARK: Lines

    /// Splits at `\n`, keeping the terminator with its line. The last line may lack one.
    static func splitLines(_ bytes: [UInt8]) -> [ArraySlice<UInt8>] {
        var lines: [ArraySlice<UInt8>] = []
        var start = 0
        for (i, byte) in bytes.enumerated() where byte == 0x0A {
            lines.append(bytes[start...i])
            start = i + 1
        }
        if start < bytes.count { lines.append(bytes[start...]) }
        return lines
    }

    // MARK: Myers diff

    /// For every index of `a` the index of the line of `b` it is matched with in a longest common
    /// subsequence, or `-1`. `nil` when the edit distance exceeds `maxEditDistance`.
    static func matching(_ a: [Int], _ b: [Int]) -> [Int]? {
        var result = [Int](repeating: -1, count: a.count)
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { result[prefix] = prefix; prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            result[a.count - 1 - suffix] = b.count - 1 - suffix
            suffix += 1
        }
        let n = a.count - prefix - suffix, m = b.count - prefix - suffix
        if n == 0 || m == 0 { return result }

        let cap = min(n + m, maxEditDistance)
        let offset = cap + 1
        var v = [Int](repeating: 0, count: 2 * cap + 3)
        // trace[d][k + d] = furthest x on diagonal k after round d.
        var trace: [[Int]] = []
        var foundD = -1
        search: for d in 0...cap {
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                    x = v[offset + k + 1]
                } else {
                    x = v[offset + k - 1] + 1
                }
                var y = x - k
                while x < n, y < m, a[prefix + x] == b[prefix + y] { x += 1; y += 1 }
                v[offset + k] = x
                if x >= n && y >= m {
                    var snap = [Int](repeating: 0, count: 2 * d + 1)
                    for kk in stride(from: -d, through: d, by: 2) { snap[kk + d] = v[offset + kk] }
                    trace.append(snap)
                    foundD = d
                    break search
                }
                k += 2
            }
            var snap = [Int](repeating: 0, count: 2 * d + 1)
            for kk in stride(from: -d, through: d, by: 2) { snap[kk + d] = v[offset + kk] }
            trace.append(snap)
        }
        guard foundD >= 0 else { return nil }

        var x = n, y = m
        var d = foundD
        while d > 0 {
            let prev = trace[d - 1]
            let k = x - y
            let prevK: Int
            if k == -d || (k != d && prev[k - 1 + (d - 1)] < prev[k + 1 + (d - 1)]) { prevK = k + 1 } else { prevK = k - 1 }
            let prevX = prev[prevK + (d - 1)]
            let prevY = prevX - prevK
            while x > prevX && y > prevY {
                result[prefix + x - 1] = prefix + y - 1
                x -= 1; y -= 1
            }
            x = prevX; y = prevY
            d -= 1
        }
        while x > 0 && y > 0 {
            result[prefix + x - 1] = prefix + y - 1
            x -= 1; y -= 1
        }
        return result
    }
}
