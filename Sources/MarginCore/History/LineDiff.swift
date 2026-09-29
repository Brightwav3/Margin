import Foundation

/// Line diff by longest common subsequence.
///
/// The common lines at both ends are peeled off first (typical edits touch one place), the middle is
/// solved by dynamic programming. When the middle is so large that the table would exceed
/// `maxCells`, it is reported as "all old lines removed, all new lines added": still correct, just
/// not minimal. Line breaks split on `\n`; a `\r` stays part of the line, so a CRLF change shows.
public enum LineDiff {
    public static let maxCells = 4_000_000

    public static func lines(of text: String) -> [String] {
        if text.isEmpty { return [] }
        // Split the bytes: as Characters, "\r\n" is one character and would never match "\n".
        var parts = text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        // A final line break does not start another line.
        if text.utf8.last == UInt8(ascii: "\n") { parts.removeLast() }
        return parts
    }

    public static func diff(old: String, new: String) -> NoteDiff {
        diff(oldLines: lines(of: old), newLines: lines(of: new))
    }

    public static func diff(oldLines a: [String], newLines b: [String]) -> NoteDiff {
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let midA = Array(a[prefix..<(a.count - suffix)]), midB = Array(b[prefix..<(b.count - suffix)])

        var out: [DiffLine] = []
        out.reserveCapacity(a.count + b.count)
        for i in 0..<prefix { out.append(DiffLine(kind: .equal, text: a[i], oldLine: i + 1, newLine: i + 1)) }
        let ops = middle(midA, midB)
        var i = prefix, j = prefix
        for op in ops {
            switch op {
            case .equal: out.append(DiffLine(kind: .equal, text: a[i], oldLine: i + 1, newLine: j + 1)); i += 1; j += 1
            case .removed: out.append(DiffLine(kind: .removed, text: a[i], oldLine: i + 1, newLine: nil)); i += 1
            case .added: out.append(DiffLine(kind: .added, text: b[j], oldLine: nil, newLine: j + 1)); j += 1
            }
        }
        for k in 0..<suffix {
            out.append(DiffLine(kind: .equal, text: a[a.count - suffix + k], oldLine: a.count - suffix + k + 1, newLine: b.count - suffix + k + 1))
        }
        return NoteDiff(lines: out)
    }

    private static func middle(_ a: [String], _ b: [String]) -> [DiffLine.Kind] {
        if a.isEmpty { return Array(repeating: .added, count: b.count) }
        if b.isEmpty { return Array(repeating: .removed, count: a.count) }
        let n = a.count, m = b.count
        guard (n + 1) * (m + 1) <= maxCells else {
            return Array(repeating: .removed, count: n) + Array(repeating: .added, count: m)
        }
        // table[i][j] = length of the LCS of a[i...] and b[j...]
        let width = m + 1
        var table = [UInt32](repeating: 0, count: (n + 1) * width)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i * width + j] = a[i] == b[j]
                    ? table[(i + 1) * width + j + 1] + 1
                    : max(table[(i + 1) * width + j], table[i * width + j + 1])
            }
        }
        var ops: [DiffLine.Kind] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] { ops.append(.equal); i += 1; j += 1 }
            else if table[(i + 1) * width + j] >= table[i * width + j + 1] { ops.append(.removed); i += 1 }
            else { ops.append(.added); j += 1 }
        }
        while i < n { ops.append(.removed); i += 1 }
        while j < m { ops.append(.added); j += 1 }
        return ops
    }
}
