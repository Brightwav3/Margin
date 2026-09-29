/// Word and task counts of one body of text (the numbers behind `NoteStats` that depend on the text).
public struct NoteTextCounts: Sendable, Hashable {
    public var words: Int
    public var openTasks: Int
    public var totalTasks: Int

    public init(words: Int = 0, openTasks: Int = 0, totalTasks: Int = 0) {
        self.words = words; self.openTasks = openTasks; self.totalTasks = totalTasks
    }
}

/// Counts for a whole text, from scratch.
public enum NoteStatsCalculator {
    /// Words (runs of non-whitespace) and open/total tasks outside code.
    public static func count(body: String) -> (words: Int, openTasks: Int, totalTasks: Int) {
        let c = NoteStatsTracker.fullCount(body)
        return (c.words, c.openTasks, c.totalTasks)
    }
}

/// Keeps the counts of a text that is being edited and recomputes only what an edit changed.
///
/// The text is compared line by line with the previous one; the lines before the first and after
/// the last difference are skipped:
/// - **Words** are a sum over lines (a word never spans a line break), so the counts of the changed
///   lines are swapped out.
/// - **Tasks** depend on context (fences, indentation, lists). They are recounted with a full scan
///   only when a changed line could matter: it is blank or indented, contains `[`, a backtick or `~`,
///   or starts with a list, heading, quote or number marker. Editing ordinary prose leaves the task
///   counts as they were.
///
/// The result always equals `NoteStatsCalculator.count(body:)` (checked by a fuzz test).
public struct NoteStatsTracker: Sendable {
    private var lines: [Substring] = []
    private var lineWords: [Int] = []
    private var counts = NoteTextCounts()
    private var primed = false

    public init() {}

    /// Counts of the text last passed to `update`.
    public var current: NoteTextCounts { counts }

    /// Recomputes the counts for `body`.
    @discardableResult
    public mutating func update(body: String) -> NoteTextCounts {
        let new = body.split(separator: "\n", omittingEmptySubsequences: false)
        guard primed else {
            lines = new
            lineWords = new.map { NoteIndex.wordCount(String($0)) }
            counts = Self.fullCount(body)
            primed = true
            return counts
        }
        var prefix = 0
        let common = min(lines.count, new.count)
        while prefix < common, lines[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < common - prefix, lines[lines.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let oldRange = prefix..<(lines.count - suffix)
        let newRange = prefix..<(new.count - suffix)
        if oldRange.isEmpty && newRange.isEmpty { return counts }

        let newWords = new[newRange].map { NoteIndex.wordCount(String($0)) }
        counts.words += newWords.reduce(0, +) - lineWords[oldRange].reduce(0, +)
        let touchesTasks = lines[oldRange].contains(where: Self.mayAffectTasks) || new[newRange].contains(where: Self.mayAffectTasks)
        lineWords.replaceSubrange(oldRange, with: newWords)
        lines = new
        if touchesTasks {
            let c = Self.fullCount(body)
            counts.openTasks = c.openTasks; counts.totalTasks = c.totalTasks
        }
        return counts
    }

    static func fullCount(_ body: String) -> NoteTextCounts {
        let tasks = MarkdownScanner().scan(body).tasks
        return NoteTextCounts(words: NoteIndex.wordCount(body), openTasks: tasks.lazy.filter { !$0.done }.count,
                              totalTasks: tasks.count)
    }

    /// Whether a line can change how tasks are read (see the type's documentation).
    static func mayAffectTasks(_ line: Substring) -> Bool {
        guard let first = line.utf8.first else { return true }                         // blank
        if first == 0x20 || first == 0x09 || first == 0x0D { return true }             // indented or blank
        if (0x30...0x39).contains(first) { return true }                                // ordered list marker
        switch first {
        case UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "#"), UInt8(ascii: ">"): return true
        default: break
        }
        for byte in line.utf8 where byte == 0x5B || byte == 0x60 || byte == 0x7E { return true }
        return false
    }
}
