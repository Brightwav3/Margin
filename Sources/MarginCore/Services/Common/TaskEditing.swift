/// Task writes shared by the fixture and the vault task services.
enum TaskEditing {
    /// Ids of exams (`exam-<id>`) are derived from courses and are not tasks in a file.
    static func requireTask(id: String) throws {
        if id.hasPrefix("exam-") { throw MarginError.invalid("An exam is not a checkbox task: \(id)") }
    }

    /// Flips the task `id` of note `noteID` inside `text`, locating it again in the text (the line
    /// the index reported may be out of date).
    static func toggle(id: String, noteID: NoteID, in text: String, extractor: TaskExtractor) throws -> String {
        let task = extractor.extract(from: text).first { extractor.taskItem($0, noteID: noteID).id == id }
        guard let task else {
            throw MarginError.conflict("Task \(id) is no longer in \(noteID); read the note again")
        }
        return try TaskToggle.toggled(text, line: task.line)
    }
}
