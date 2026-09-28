/// Task writes shared by the fixture and the vault task services.
enum TaskEditing {
    /// Ids of exams (`exam-<id>`) are derived from courses and are not tasks in a file.
    static func requireTask(id: String) throws {
        if id.hasPrefix("exam-") { throw MarginError.invalid("An exam is not a checkbox task: \(id)") }
    }
}
