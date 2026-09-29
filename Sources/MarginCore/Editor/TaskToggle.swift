/// Flips a task checkbox in markdown text: `- [ ]` becomes `- [x]` and back.
///
/// Only the one character inside the brackets changes; every other byte of the text (line endings,
/// BOM, the rest of the line, other tasks) stays as it was, so toggling twice returns the original.
public enum TaskToggle {
    /// `text` with the task on 1-based `line` flipped. Throws `MarginError.notFound` when the line
    /// is not a task (a task-looking line inside code is not a task, vault spec 05 §10).
    public static func toggled(_ text: String, line: Int) throws -> String {
        try set(text, line: line, done: nil).text
    }

    /// `text` with the task on `line` set to `done` (no change when it already is).
    public static func setting(_ text: String, line: Int, done: Bool) throws -> String {
        try set(text, line: line, done: done).text
    }

    /// The task's state after the edit, and the new text.
    static func set(_ text: String, line: Int, done: Bool?) throws -> (text: String, done: Bool) {
        guard let task = MarkdownScanner().scan(text).tasks.first(where: { $0.line == line }) else {
            throw MarginError.notFound("No task on line \(line)")
        }
        var bytes = Array(text.utf8)
        // Marker, then whitespace, then `[`, the mark and `]` (the scanner already checked the shape).
        var i = task.range.start
        let end = min(task.range.end, bytes.count)
        func isWS(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 }
        while i < end, isWS(bytes[i]) { i += 1 }
        i += 1                                         // - * +
        while i < end, isWS(bytes[i]) { i += 1 }
        guard i + 2 < end, bytes[i] == 0x5B, bytes[i + 2] == 0x5D else {
            throw MarginError.invalid("Line \(line) is not a well-formed task")
        }
        let newDone = done ?? !task.done
        if newDone != task.done {
            bytes[i + 1] = newDone ? 0x78 : 0x20
        }
        return (String(decoding: bytes, as: UTF8.self), newDone)
    }
}
