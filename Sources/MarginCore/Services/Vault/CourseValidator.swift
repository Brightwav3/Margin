import Foundation

/// Checks a `_course.md` against the format of `docs/plan/05-vault-spec.md` §5. Used before the
/// app writes a course file, and by tests to show that what the app writes reads back.
///
/// Errors are `MarginError.invalid`. A hand-edited file may break these rules and the app still
/// opens it (`VaultCourseModel` is tolerant); the validator is for what the app itself writes.
/// Unknown keys are fine (spec §2: unknown keys are kept).
public enum CourseValidator {
    /// Every problem in `text`; empty when the file is a valid course.
    public static func validate(_ text: String) -> [MarginError] {
        let (fm, _) = Frontmatter.parse(text)
        guard let fm else { return [.invalid("_course.md has no frontmatter block")] }
        return validate(fm)
    }

    /// Every problem in `fm`; empty when it describes a valid course.
    public static func validate(_ fm: Frontmatter) -> [MarginError] {
        var problems = fm.validate()
        func bad(_ message: String) { problems.append(.invalid(message)) }

        if (fm.string(for: "name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty {
            bad("A course needs a 'name'")
        }
        if let id = fm.string(for: "id"), id.isEmpty || id != NoteIndex.slug(id) {
            bad("The course 'id' must be a slug (lower-case letters, digits, '-'), not '\(id)'")
        }
        if fm.contains("credits"), fm.number(for: "credits").map({ $0 < 0 }) ?? true { bad("'credits' must be a number, 0 or more") }

        var sessionIDs = Set<String>()
        for (i, item) in (fm.list(for: "sessions") ?? []).enumerated() {
            guard let day = item["day"]?.stringValue.flatMap({ Weekday(token: $0) }) else { bad("sessions[\(i)]: 'day' is missing or not a weekday"); continue }
            guard let time = item["time"]?.stringValue.flatMap({ LocalTime(string: $0) }) else { bad("sessions[\(i)]: 'time' is missing or not HH:MM"); continue }
            if let length = item["length"] {
                guard let hours = length.numberValue, hours > 0, hours <= 12 else { bad("sessions[\(i)]: 'length' must be more than 0 and at most 12 hours"); continue }
            }
            if !sessionIDs.insert("\(day.rawValue)-\(time.string)").inserted { bad("sessions[\(i)]: two sessions on \(day.rawValue) at \(time)") }
        }
        for (i, item) in (fm.list(for: "exams") ?? []).enumerated() {
            if item["title"]?.stringValue == nil { bad("exams[\(i)]: 'title' is missing") }
            if item["date"]?.dateValue == nil { bad("exams[\(i)]: 'date' is missing or not YYYY-MM-DD") }
        }
        var total = 0
        for (i, item) in (fm.list(for: "grading") ?? []).enumerated() {
            if item["label"]?.stringValue == nil { bad("grading[\(i)]: 'label' is missing") }
            guard let weight = VaultCourseModel.percent(item["weight"]), (0...100).contains(weight) else {
                bad("grading[\(i)]: 'weight' must be a percentage from 0 to 100"); continue
            }
            total += weight
        }
        if total > 100 { bad("The grading weights add up to \(total)%, more than 100%") }
        // Named by content, not position, so rewriting the list does not make an old problem look new.
        for item in fm.list(for: "overrides") ?? [] where SessionOverrideCodec.decode(item, courseID: "") == nil {
            bad("overrides: '\(YAMLSubset.renderInline(item, flow: true).prefix(60))' needs 'session', 'date' and one of 'cancelled: true', 'start' or 'room'")
        }
        return problems
    }
}
