import Foundation

/// Which ids are taken while ids are assigned across several notes.
///
/// - `reserved`: every id that exists anywhere in the vault (or was generated), so a generated id
///   never collides with one that a note processed later already carries.
/// - `claimed`: ids already owned by an earlier note or task in processing order. An id met a
///   second time is a duplicate and is reassigned; the first owner keeps it.
public struct IDLedger: Sendable, Hashable {
    public private(set) var reserved: Set<String>
    public private(set) var claimed: Set<String>

    public init(reserved: Set<String> = [], claimed: Set<String> = []) {
        self.reserved = reserved.union(claimed)
        self.claimed = claimed
    }

    /// Marks `id` as owned. Returns `false` when someone owned it already (a duplicate).
    mutating func claim(_ id: String) -> Bool {
        reserved.insert(id)
        return claimed.insert(id).inserted
    }

    /// Reserves and claims a freshly generated id.
    mutating func adopt(_ id: String) {
        reserved.insert(id)
        claimed.insert(id)
    }
}

/// What happened to the note's own id.
public enum NoteIDOutcome: Sendable, Hashable {
    /// The note already had an id, which is left untouched.
    case kept
    /// The note had no id; one was added to the frontmatter.
    case added
    /// The id was already used by an earlier note; a new one replaced it.
    case replacedDuplicate(old: String)
    /// The note was not touched because its frontmatter cannot be edited safely.
    case skipped(reason: String)
}

/// What happened to one task's id.
public enum TaskIDOutcome: Sendable, Hashable {
    /// The line already ended in a `^block` id, which is now the task id.
    case kept
    /// `^t-…` was appended to the line.
    case added
    /// The id was already used by an earlier task; a new one replaced it.
    case replacedDuplicate(old: String)
    /// A duplicate id that could not be replaced (the id is not where the extractor found it).
    case duplicateKept
}

/// The id of one task after assignment.
public struct AssignedTask: Sendable, Hashable {
    /// 1-based line in the original text (a note id added to the frontmatter shifts the lines of
    /// the new text).
    public var line: Int
    /// The id the task has in the new text, without the caret.
    public var id: String
    public var outcome: TaskIDOutcome
    /// The task text without due token and id.
    public var text: String
}

/// Result of `IDAssigner.assign`.
public struct IDAssignmentResult: Sendable, Hashable {
    public var original: String
    /// The new text. Equal to `original` when nothing had to be assigned.
    public var text: String
    /// The note's id in the new text, `nil` when the frontmatter is not editable.
    public var noteID: String?
    public var noteOutcome: NoteIDOutcome
    /// Every real task (never inside code or frontmatter), in document order.
    public var tasks: [AssignedTask]

    public var didChange: Bool { text != original }
}

/// Adds the missing stable ids to a note's text (spec 05 §3 and §12, D-012).
///
/// - The note id goes into the frontmatter as `id: n-xxxx`, through the lossless `Frontmatter`
///   writer; a note without frontmatter gets a new block in the file's line ending style (after a
///   BOM if there is one). An existing `id:` is never changed unless it is a duplicate of one
///   owned by an earlier note.
/// - Every task line gets `^t-xxxx` appended at the very end of the line. A line that already ends
///   in a `^block` id keeps that id as the task id (no second id is added; the Obsidian block id
///   stays valid).
/// - Nothing else changes: all other bytes (CRLF, BOM, trailing spaces, code) stay identical, and
///   the operation is idempotent.
/// - A note whose frontmatter cannot be edited safely (unterminated `---`, a malformed block, an
///   `id:` that is a list or map) gets no note id (`NoteIDOutcome.skipped`); its tasks are still
///   handled.
public struct IDAssigner: Sendable {
    private let scanner = MarkdownScanner()

    public init() {}

    // MARK: Inspecting

    /// The ids a text already carries: the note id and the `^id` of each task line.
    public func existingIDs(in text: String) -> (note: String?, tasks: [String]) {
        let note = Frontmatter.parse(text).frontmatter.flatMap(Self.noteID(of:))
        var tasks: [String] = []
        for t in scanner.scan(text).tasks {
            if let id = TaskExtractor.parse(rawText: t.rawText).blockID { tasks.append(id) }
        }
        return (note, tasks)
    }

    /// The id stored in `fm`, `nil` when absent, empty or `null`.
    static func noteID(of fm: Frontmatter) -> String? {
        guard let s = fm.string(for: "id")?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }

    // MARK: Assigning

    /// Assigns ids for a single note. `existing` are ids used elsewhere that must not be
    /// generated; duplicates are detected within this note only.
    public func assign(to text: String, generator: inout StableIDGenerator,
                       existing: Set<String> = []) -> IDAssignmentResult {
        let own = existingIDs(in: text)
        var ledger = IDLedger(reserved: existing.union([own.note].compactMap { $0 }).union(own.tasks))
        return assign(to: text, ledger: &ledger, generator: &generator)
    }

    /// Assigns ids for a note processed in a vault-wide run. `ledger.reserved` must already hold
    /// every id of the vault (see `existingIDs(in:)`); notes are processed in path order.
    public func assign(to text: String, ledger: inout IDLedger,
                       generator: inout StableIDGenerator) -> IDAssignmentResult {
        // A BOM is not part of the first line: work on the text behind it and put it back.
        if text.unicodeScalars.first == "\u{FEFF}" {
            var inner = assign(to: String(text.unicodeScalars.dropFirst()), ledger: &ledger, generator: &generator)
            inner.original = text
            inner.text = "\u{FEFF}" + inner.text
            return inner
        }
        let bytes = Array(text.utf8)

        // 1. Note id decision (from the original frontmatter).
        let parsed = Frontmatter.parse(text)
        var noteAction = NoteAction.keep
        var noteID: String?
        var noteOutcome = NoteIDOutcome.kept
        if let fm = parsed.frontmatter {
            if !fm.isValid {
                noteOutcome = .skipped(reason: "frontmatter is malformed")
            } else if fm.contains("id"), Self.noteID(of: fm) == nil,
                      let v = fm.value(for: "id"), !Self.isEmptyScalar(v) {
                noteOutcome = .skipped(reason: "id is not a scalar")
            } else if let existing = Self.noteID(of: fm) {
                if ledger.claim(existing) {
                    noteID = existing
                } else {
                    let new = generator.next(.note, avoiding: ledger.reserved)
                    ledger.adopt(new)
                    noteAction = .replace(new)
                    noteID = new
                    noteOutcome = .replacedDuplicate(old: existing)
                }
            } else {
                let new = generator.next(.note, avoiding: ledger.reserved)
                ledger.adopt(new)
                noteAction = .set(new)
                noteID = new
                noteOutcome = .added
            }
        } else if Self.startsWithUnclosedFence(bytes) {
            noteOutcome = .skipped(reason: "frontmatter is not terminated")
        } else {
            let new = generator.next(.note, avoiding: ledger.reserved)
            ledger.adopt(new)
            noteAction = .create(new)
            noteID = new
            noteOutcome = .added
        }

        // 2. Task edits, as byte edits on the original text.
        var edits: [(range: Range<Int>, insert: [UInt8])] = []
        var tasks: [AssignedTask] = []
        for t in scanner.scan(text).tasks {
            let parsedTask = TaskExtractor.parse(rawText: t.rawText)
            let lineStart = min(t.range.start, bytes.count)
            var contentEnd = min(t.range.end, bytes.count)
            if contentEnd > lineStart, bytes[contentEnd - 1] == 0x0A { contentEnd -= 1 }
            if contentEnd > lineStart, bytes[contentEnd - 1] == 0x0D { contentEnd -= 1 }

            if let id = parsedTask.blockID {
                if ledger.claim(id) {
                    tasks.append(AssignedTask(line: t.line, id: id, outcome: .kept, text: parsedTask.text))
                } else if let r = Self.trailingIDRange(bytes, lineStart: lineStart, contentEnd: contentEnd, id: id) {
                    let new = generator.next(.task, avoiding: ledger.reserved)
                    ledger.adopt(new)
                    edits.append((r, Array(new.utf8)))
                    tasks.append(AssignedTask(line: t.line, id: new, outcome: .replacedDuplicate(old: id), text: parsedTask.text))
                } else {
                    tasks.append(AssignedTask(line: t.line, id: id, outcome: .duplicateKept, text: parsedTask.text))
                }
            } else {
                let new = generator.next(.task, avoiding: ledger.reserved)
                ledger.adopt(new)
                let endsInSpace = contentEnd > lineStart && Self.isSpaceByte(bytes[contentEnd - 1])
                let suffix = (endsInSpace ? "" : " ") + "^" + new
                edits.append((contentEnd..<contentEnd, Array(suffix.utf8)))
                tasks.append(AssignedTask(line: t.line, id: new, outcome: .added, text: parsedTask.text))
            }
        }

        var out = bytes
        for e in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            out.replaceSubrange(e.range, with: e.insert)
        }
        var result = String(decoding: out, as: UTF8.self)

        // 3. Note id, applied to the task-edited text (task edits never touch the frontmatter).
        switch noteAction {
        case .keep: break
        case .set(let id), .replace(let id):
            let (fm, body) = Frontmatter.parse(result)
            if var fm {
                fm.set("id", .string(id))
                result = fm.render(body: body)
            }
        case .create(let id):
            result = Self.creating(id: id, in: result)
        }

        return IDAssignmentResult(original: text, text: result, noteID: noteID,
                                  noteOutcome: noteOutcome, tasks: tasks)
    }

    // MARK: Internals

    private enum NoteAction { case keep, set(String), replace(String), create(String) }

    private static func isEmptyScalar(_ v: FrontmatterValue) -> Bool {
        switch v {
        case .null: true
        case .string(let s): s.trimmingCharacters(in: .whitespaces).isEmpty
        default: false
        }
    }

    private static func isSpaceByte(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 }

    /// A first line of `---` without any closing fence: the text may be a
    /// broken frontmatter block, so no new one is put in front of it.
    private static func startsWithUnclosedFence(_ bytes: [UInt8]) -> Bool {
        var end = 0
        while end < bytes.count, bytes[end] != 0x0A { end += 1 }
        var content = bytes[0..<end]
        while let l = content.last, l == 0x0D || l == 0x20 || l == 0x09 { content = content.dropLast() }
        return Array(content) == [0x2D, 0x2D, 0x2D]
    }

    /// Text with a new frontmatter block `id: <id>` in front, in the text's line ending style.
    private static func creating(id: String, in text: String) -> String {
        let nl = usesCRLF(text) ? "\r\n" : "\n"
        var fm = Frontmatter()
        fm.opening = "---" + nl
        fm.closing = "---" + nl
        fm.set("id", .string(id))
        return fm.render() + text
    }

    /// `true` when the first line break of `text` is CRLF.
    private static func usesCRLF(_ text: String) -> Bool {
        var previous: UInt8 = 0
        for b in text.utf8 {
            if b == 0x0A { return previous == 0x0D }
            previous = b
        }
        return false
    }

    /// Byte range of the id characters (after the caret) of the trailing `^id` on the line, found
    /// with the same rules as `TaskExtractor.parse`; `nil` when it is not exactly `id`.
    private static func trailingIDRange(_ bytes: [UInt8], lineStart: Int, contentEnd: Int, id: String) -> Range<Int>? {
        guard lineStart <= contentEnd else { return nil }
        let line = String(decoding: bytes[lineStart..<contentEnd], as: UTF8.self)
        let chars = Array(line)
        var end = chars.count
        while end > 0, chars[end - 1].isWhitespace { end -= 1 }
        var start = end
        while start > 0, chars[start - 1].isASCII, chars[start - 1].isLetter || chars[start - 1].isNumber || chars[start - 1] == "-" {
            start -= 1
        }
        guard start < end, start > 0, chars[start - 1] == "^", String(chars[start..<end]) == id else { return nil }
        let prefixBytes = String(chars[..<start]).utf8.count
        let idBytes = id.utf8.count
        return (lineStart + prefixBytes)..<(lineStart + prefixBytes + idBytes)
    }
}
