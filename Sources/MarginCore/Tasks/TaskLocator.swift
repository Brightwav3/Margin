/// What is known about a task that has to be found again in its source note.
///
/// Built from a `TaskItem` that may be stale (the note was edited since the item was read).
public struct TaskTarget: Sendable, Hashable {
    /// The `^id` the task carried, if it had one.
    public var blockID: String?
    /// The task text without due token and `^id` (`TaskItem.text`).
    public var text: String
    /// 1-based line where the task was last seen.
    public var line: Int

    public init(blockID: String?, text: String, line: Int) {
        self.blockID = blockID; self.text = text; self.line = line
    }

    /// The target for `item`. A location-derived id (`<note>#L<line>`, used until a task has a
    /// `^id`) says nothing about the task, so it is not used as a block id.
    public init(item: TaskItem) {
        let derived = "\(item.source.noteID)#L"
        let isDerived = item.id.hasPrefix(derived) && Int(item.id.dropFirst(derived.count)) != nil
        self.init(blockID: isDerived ? nil : item.id, text: item.text, line: item.source.line)
    }
}

/// A task found again, and how.
public struct TaskMatch: Sendable, Hashable {
    public enum Method: String, Sendable, Hashable {
        /// The `^id` matched.
        case blockID
        /// The text matched exactly.
        case exactText
        /// The text is close enough (a typo fixed, a word added).
        case fuzzy
    }

    public var task: ExtractedTask
    public var method: Method
}

/// Finds a task in the current tasks of its note after the note was edited (M7-09.B).
///
/// Order of attempts, first success wins:
/// 1. **`^id`.** Unique match wins. If the id occurs several times (a copied line), the copy with
///    the same text nearest to the old line wins.
/// 2. **Exact text.** A unique match wins wherever it is; among several, the one nearest to the
///    old line. Two equally near matches are ambiguous and count as not found.
/// 3. **Fuzzy text.** Normalised (case, whitespace) text with a similarity of at least
///    `fuzzyThreshold`; the best score wins, near-equal scores are decided by distance to the old
///    line and remaining ties count as not found.
///
/// Ambiguity returns `nil` rather than guessing: a wrong line means the wrong task gets written.
public enum TaskLocator {
    /// Minimum similarity (0…1) for a fuzzy match.
    public static let fuzzyThreshold = 0.8
    /// Fuzzy matching is skipped for texts shorter than this many characters.
    static let fuzzyMinimumLength = 4
    /// Texts longer than this are not compared character by character.
    static let fuzzyMaximumLength = 300
    /// Scores closer than this count as equal.
    static let scoreTolerance = 0.03

    public static func resolve(_ target: TaskTarget, in tasks: [ExtractedTask]) -> TaskMatch? {
        if let id = target.blockID {
            let byID = tasks.filter { $0.blockID == id }
            if byID.count == 1, let t = byID.first { return TaskMatch(task: t, method: .blockID) }
            if byID.count > 1 {
                let sameText = byID.filter { $0.text == target.text }
                if let t = nearest(sameText.isEmpty ? byID : sameText, to: target.line) {
                    return TaskMatch(task: t, method: .blockID)
                }
                return nil
            }
        }

        let exact = tasks.filter { $0.text == target.text }
        if let t = nearest(exact, to: target.line) { return TaskMatch(task: t, method: .exactText) }
        if !exact.isEmpty { return nil }   // ambiguous: several equally near

        return fuzzy(target, in: tasks).map { TaskMatch(task: $0, method: .fuzzy) }
    }

    /// The task nearest to `line`; `nil` when there is none or two are equally near.
    private static func nearest(_ tasks: [ExtractedTask], to line: Int) -> ExtractedTask? {
        guard let best = tasks.map({ abs($0.line - line) }).min() else { return nil }
        let closest = tasks.filter { abs($0.line - line) == best }
        return closest.count == 1 ? closest[0] : nil
    }

    private static func fuzzy(_ target: TaskTarget, in tasks: [ExtractedTask]) -> ExtractedTask? {
        let wanted = normalise(target.text)
        guard wanted.count >= fuzzyMinimumLength, wanted.count <= fuzzyMaximumLength else { return nil }
        let scored: [(task: ExtractedTask, score: Double)] = tasks.compactMap { t in
            let s = normalise(t.text)
            guard s.count >= fuzzyMinimumLength, s.count <= fuzzyMaximumLength else { return nil }
            let score = similarity(wanted, s)
            return score >= fuzzyThreshold ? (t, score) : nil
        }
        guard let top = scored.map(\.score).max() else { return nil }
        let leaders = scored.filter { top - $0.score <= scoreTolerance }.map(\.task)
        return nearest(leaders, to: target.line)
    }

    static func normalise(_ text: String) -> [Character] {
        Array(text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
    }

    /// 1 - edit distance / longer length.
    static func similarity(_ a: [Character], _ b: [Character]) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        let longer = max(a.count, b.count)
        return 1 - Double(editDistance(a, b)) / Double(longer)
    }

    /// Levenshtein distance with two rows.
    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
