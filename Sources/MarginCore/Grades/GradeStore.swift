import Foundation

/// Reads and writes `_grades.md` (spec 05 §7).
///
/// **Format chosen** (the spec allows a markdown table or a frontmatter list; the list is the source
/// of truth, the table is not read):
///
/// ```
/// ---
/// grades:
///   - {item: Problem set 1, group: Problem sets, weight: 5%, score: 19, max: 20, date: 2026-09-21}
///   - {item: Midterm, group: Midterm, weight: 30%, date: 2026-10-01}
/// ---
/// (anything below is the user's, kept byte for byte)
/// ```
///
/// - `item` is required; `group` (a `grading` label of `_course.md`), `weight` (`5%` or `5`), `score`,
///   `max` and `date` are optional. An item without `score` is pending.
/// - Other keys of an entry and of the file are ignored on read and lost when the entry is rewritten
///   (the app only ever appends; it never rewrites an existing entry). Other frontmatter keys and the
///   body are kept byte for byte.
/// - A table in the body is a view the app does not maintain or read.
/// - Ids are `grade-<course>-<slug of item>`; equal slugs get `-2`, `-3`, … in file order.
public enum GradeStore {
    public static let fileName = "_grades.md"
    public static let listKey = "grades"

    /// The id of the item named `item` in `course` (before de-duplication).
    public static func baseID(course: CourseID, item: String) -> String {
        "grade-\(course)-\(NoteIndex.slug(item))"
    }

    /// Items of a `_grades.md` text. Entries without an `item` are skipped.
    public static func parse(_ content: String, course: CourseID) -> [Grade] {
        guard let fm = Frontmatter.parse(content).frontmatter else { return [] }
        var seen: [String: Int] = [:]
        var result: [Grade] = []
        for entry in fm.list(for: listKey) ?? [] {
            guard let item = entry["item"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !item.isEmpty else { continue }
            let base = baseID(course: course, item: item)
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            result.append(Grade(
                id: n == 1 ? base : "\(base)-\(n)", courseID: course, item: item,
                group: entry["group"]?.stringValue, weightPercent: VaultCourseModel.percent(entry["weight"]),
                score: entry["score"]?.numberValue, max: entry["max"]?.numberValue, date: entry["date"]?.dateValue))
        }
        return result
    }

    /// Checks a grade before it is written.
    public static func validate(_ grade: Grade) throws -> Grade {
        var g = grade
        g.item = grade.item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g.item.isEmpty else { throw MarginError.invalid("A grade needs an item name") }
        guard !g.item.containsLineBreak else { throw MarginError.invalid("A grade item name is one line") }
        if let group = g.group?.trimmingCharacters(in: .whitespacesAndNewlines) { g.group = group.isEmpty ? nil : group }
        if let max = g.max, !(max > 0 && max.isFinite) { throw MarginError.invalid("'max' must be above 0") }
        if let score = g.score {
            guard score.isFinite, score >= 0 else { throw MarginError.invalid("'score' must be 0 or more") }
            guard g.max != nil else { throw MarginError.invalid("A score needs a 'max'") }
        }
        if let w = g.weightPercent, !(0...100).contains(w) { throw MarginError.invalid("'weight' must be from 0 to 100") }
        return g
    }

    /// The frontmatter entry of a grade.
    static func entry(_ g: Grade) -> FrontmatterValue {
        var pairs: [FrontmatterValue.Pair] = [.init("item", .string(g.item))]
        if let v = g.group { pairs.append(.init("group", .string(v))) }
        if let v = g.weightPercent { pairs.append(.init("weight", .string("\(v)%"))) }
        if let v = g.score { pairs.append(.init("score", .number(v))) }
        if let v = g.max { pairs.append(.init("max", .number(v))) }
        if let v = g.date { pairs.append(.init("date", .date(v))) }
        return .map(pairs)
    }

    /// The text of `_grades.md` with `grade` appended (validated). `content == nil` is a new file.
    /// Throws `.conflict` when an item of that name exists.
    public static func appending(_ grade: Grade, to content: String?, course: CourseID, courseName: String) throws -> String {
        let g = try validate(grade)
        let existing = content.map { parse($0, course: course) } ?? []
        if existing.contains(where: { $0.item.caseInsensitiveCompare(g.item) == .orderedSame }) {
            throw MarginError.conflict("\(courseName) already has a grade named \(g.item)")
        }
        guard let content else {
            var fm = Frontmatter()
            fm.set(listKey, .list([entry(g)]))
            return fm.render() + "\n# Grades — \(courseName)\n"
        }
        let (parsed, body) = Frontmatter.parse(content)
        guard var fm = parsed else {
            // A file without a frontmatter block: the block goes in front, the text stays.
            var fresh = Frontmatter()
            fresh.set(listKey, .list([entry(g)]))
            return fresh.render() + content
        }
        if let problem = fm.validate().first { throw problem }
        var list = fm.list(for: listKey) ?? []
        list.append(entry(g))
        fm.set(listKey, .list(list))
        return fm.render() + body
    }

    /// The text a course with these items would have (the fixture's stand-in for the file, so
    /// versions change exactly when the items do).
    public static func canonicalText(_ grades: [Grade], course: CourseID, courseName: String) -> String {
        var fm = Frontmatter()
        fm.set(listKey, .list(grades.map(entry)))
        return fm.render() + "\n# Grades — \(courseName)\n"
    }
}
