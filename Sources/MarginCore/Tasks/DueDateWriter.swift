import Foundation

/// Writes a due date into a task line, or removes it (M10-10.B; spec 05 §3).
///
/// The due token is `@` plus a word (`@2026-10-02`, `@Tue`, `@before-midterm`), recognised by the
/// same grammar as `TaskExtractor` (the last word after `@` that parses as a `DueToken`). Setting a
/// date writes it as an ISO token, the one form that means the same on every day:
///
/// - the task has a token: it is replaced in place (`@ Tue` and `@tomorrow` become `@2026-10-02`),
///   the words around it stay where they are,
/// - it has none: ` @2026-10-02` is appended to the text, before the block id,
/// - the block id (`^t-4f2a`) stays at the end of the line, with the whitespace before it as it was,
/// - other `@words` (mentions) are text and are never touched,
/// - the checkbox, indentation, list marker, trailing whitespace and line ending stay byte for byte;
///   the rest of the file is not looked at.
///
/// Removing (`due == nil`) takes the token out and joins the words around it with one space. A task
/// that would be left without any text is refused (`.invalid`), since a checkbox without text is not
/// a task any more.
enum DueDateWriter {
    /// `content` with the due date of `task` set to `due` (removed for `nil`); `content` itself when
    /// there is nothing to change.
    /// - Throws: `.invalid` when the line is not a task line of `content` or removing the token would
    ///   leave no text.
    static func setting(_ due: LocalDate?, in content: String, task: ExtractedTask) throws -> String {
        var bytes = Array(content.utf8)
        let range = task.range
        guard range.start >= 0, range.end <= bytes.count, range.start <= range.end,
              let line = String(validating: bytes[range.start..<range.end], as: UTF8.self)
        else { throw MarginError.invalid("Line \(task.line) is not a task line") }

        var chars = Array(line)
        var trailing: [Character] = []
        while let last = chars.last, last.isWhitespace { trailing.insert(chars.removeLast(), at: 0) }
        let raw = Array(task.rawText)
        guard chars.count >= raw.count, Array(chars[(chars.count - raw.count)...]) == raw else {
            throw MarginError.invalid("Line \(task.line) is not a task line")
        }
        let head = Array(chars[..<(chars.count - raw.count)])
        guard let newRaw = edit(raw, due: due) else {
            if due == nil { return content }
            throw MarginError.invalid("Line \(task.line) is not a task line")
        }
        if newRaw.isEmpty { throw MarginError.invalid("Removing the due date would leave line \(task.line) without text") }
        let newLine = String(head + newRaw + trailing)
        if newLine == line { return content }
        bytes.replaceSubrange(range.start..<range.end, with: Array(newLine.utf8))
        return String(validating: bytes, as: UTF8.self) ?? content
    }

    /// The text after the checkbox with the due token set, or `nil` when there is nothing to remove.
    /// An empty result means the removal would leave no text.
    static func edit(_ raw: [Character], due: LocalDate?) -> [Character]? {
        // Trailing block id: `^id` after whitespace, with text before it (as `TaskExtractor` reads it).
        var body = raw
        var separator: [Character] = []
        var blockID: [Character] = []
        var end = raw.count
        while end > 0, raw[end - 1].isWhitespace { end -= 1 }
        var start = end
        while start > 0, isWordChar(raw[start - 1]) { start -= 1 }
        if start < end, start > 1, raw[start - 1] == "^", raw[start - 2].isWhitespace,
           raw[..<(start - 1)].contains(where: { !$0.isWhitespace }) {
            var textEnd = start - 1
            while textEnd > 0, raw[textEnd - 1].isWhitespace { textEnd -= 1 }
            body = Array(raw[..<textEnd])
            separator = Array(raw[textEnd..<(start - 1)])
            blockID = Array(raw[(start - 1)..<end])
        }
        let suffix = blockID.isEmpty ? [] : separator + blockID

        // The last word after `@` that is a due token.
        var found: (from: Int, to: Int)?
        var i = 0
        while i < body.count {
            if body[i] == "@", i == 0 || body[i - 1].isWhitespace {
                var j = i + 1
                while j < body.count, body[j] == " " || body[j] == "\t" { j += 1 }
                var k = j
                while k < body.count, isWordChar(body[k]) { k += 1 }
                if k > j, DueToken(word: String(body[j..<k])) != nil { found = (i, k) }
            }
            i += 1
        }

        guard let due else {
            guard let f = found else { return nil }
            let before = trimmedEnd(Array(body[..<f.from])), after = trimmedStart(Array(body[f.to...]))
            let joined = before.isEmpty ? after : (after.isEmpty ? before : before + [" "] + after)
            return joined.isEmpty ? [] : joined + suffix
        }
        let token = Array("@\(due.iso)")
        if let f = found { return Array(body[..<f.from]) + token + Array(body[f.to...]) + suffix }
        return body + [" "] + token + suffix
    }

    private static func isWordChar(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "-") }
    private static func trimmedEnd(_ a: [Character]) -> [Character] {
        var a = a
        while let l = a.last, l.isWhitespace { a.removeLast() }
        return a
    }
    private static func trimmedStart(_ a: [Character]) -> [Character] { Array(a.drop(while: { $0.isWhitespace })) }
}
