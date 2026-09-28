/// A task with parsed structure, before it is mapped to the contract's `TaskItem`.
public struct ExtractedTask: Sendable, Hashable {
    /// 1-based line of the task.
    public var line: Int
    /// Nesting depth: 0 for a top-level task, parent depth + 1 otherwise.
    public var depth: Int
    /// Line of the enclosing task in the same list, if any.
    public var parentLine: Int?
    public var done: Bool
    /// Text without the `@` due token and the `^id` suffix.
    public var text: String
    /// Text exactly as written after the checkbox.
    public var rawText: String
    /// Stable id parsed from a trailing `^t-4f2a` (without the caret). `nil` when absent; this
    /// extractor never generates ids (TODO(AG-02): ids are assigned by the app).
    public var blockID: String?
    /// The recognised due token, even when it could not be resolved (`@before-midterm` with no
    /// midterm in the context).
    public var dueToken: DueToken?
    /// The resolved due day.
    public var due: LocalDate?
    /// Byte range of the whole line.
    public var range: ByteRange
}

/// Extracts tasks from a scanned document and resolves due tokens against a `Clock`.
///
/// Due token grammar: `@` at the start of the text or after whitespace, optional spaces or tabs
/// (`@ Tue` is valid), then a word of ASCII letters, digits and `-`. The last word that parses as
/// a `DueToken` wins and is removed from `text`; other `@words` (mentions, e-mail-like text) stay
/// in the text and are ignored. A trailing ` ^id` (letters, digits, `-`) is the block id.
public struct TaskExtractor: Sendable {
    public let resolver: DueResolver
    private let scanner = MarkdownScanner()

    public init(clock: any Clock, context: CourseEventContext = .empty) {
        self.resolver = DueResolver(clock: clock, context: context)
    }

    public func extract(from text: String) -> [ExtractedTask] {
        extract(from: scanner.scan(text))
    }

    public func extract(from scan: MarkdownScan) -> [ExtractedTask] {
        var result: [ExtractedTask] = []
        var stack: [(indent: Int, line: Int, depth: Int, listID: Int)] = []
        for t in scan.tasks {
            while let top = stack.last, top.listID != t.listID || top.indent >= t.indent {
                stack.removeLast()
            }
            let parent = stack.last
            let depth = (parent?.depth ?? -1) + 1
            stack.append((t.indent, t.line, depth, t.listID))

            let parsed = Self.parse(rawText: t.rawText)
            result.append(ExtractedTask(
                line: t.line, depth: depth, parentLine: parent?.line, done: t.done,
                text: parsed.text, rawText: t.rawText, blockID: parsed.blockID,
                dueToken: parsed.token, due: parsed.token.flatMap { resolver.resolve($0) },
                range: t.range))
        }
        return result
    }

    /// Maps an extracted task to the contract type. Until AG-02 assigns ids, a task without
    /// `^id` gets the location-derived id `<noteID>#L<line>`, which is not stable across edits.
    public func taskItem(_ task: ExtractedTask, noteID: NoteID, courseID: CourseID? = nil) -> TaskItem {
        TaskItem(
            id: task.blockID ?? "\(noteID)#L\(task.line)", text: task.text, due: task.due,
            label: task.due.map { DueLabel.make(due: $0, today: resolver.clock.today) },
            done: task.done, kind: .task,
            source: TaskLocation(noteID: noteID, line: task.line, courseID: courseID))
    }

    /// Splits raw task text into clean text, block id and due token.
    static func parse(rawText: String) -> (text: String, blockID: String?, token: DueToken?) {
        var chars = Array(rawText)
        var blockID: String?

        // Trailing block id.
        var end = chars.count
        while end > 0, chars[end - 1].isWhitespace { end -= 1 }
        var start = end
        while start > 0, isWordChar(chars[start - 1]) { start -= 1 }
        if start < end, start > 0, chars[start - 1] == "^", start - 1 > 0,
           chars[start - 2].isWhitespace,
           chars[..<(start - 1)].contains(where: { !$0.isWhitespace }) {
            blockID = String(chars[start..<end])
            chars = Array(chars[..<(start - 1)])
        }

        // Due token: last parsable candidate.
        var found: (from: Int, to: Int, token: DueToken)?
        var i = 0
        while i < chars.count {
            if chars[i] == "@", i == 0 || chars[i - 1].isWhitespace {
                var j = i + 1
                while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
                var k = j
                while k < chars.count, isWordChar(chars[k]) { k += 1 }
                if k > j, let tok = DueToken(word: String(chars[j..<k])) {
                    found = (i, k, tok)
                }
            }
            i += 1
        }

        var text = String(chars)
        if let f = found {
            let before = String(chars[..<f.from]).trimmingTrailingWhitespace()
            let after = String(chars[f.to...]).trimmingLeadingWhitespace()
            text = before.isEmpty ? after : (after.isEmpty ? before : before + " " + after)
        }
        return (text.trimmingTrailingWhitespace().trimmingLeadingWhitespace(), blockID, found?.token)
    }

    private static func isWordChar(_ c: Character) -> Bool {
        guard c.isASCII else { return false }
        return c.isLetter || c.isNumber || c == "-"
    }
}

extension String {
    fileprivate func trimmingTrailingWhitespace() -> String {
        var s = Substring(self)
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return String(s)
    }

    fileprivate func trimmingLeadingWhitespace() -> String {
        String(drop(while: { $0.isWhitespace }))
    }
}
