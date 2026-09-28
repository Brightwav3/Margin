/// Maps spoken forms of course names to course ids ("bio", "BIO 201", "orgo", "cell biology").
///
/// Aliases are derived from the injected course list: full name, words of the name (5+ letters),
/// code (`bio 201`, `bio201`), code prefix (`bio`), the course id and the professor's surname
/// (lowest priority). Common nicknames come from a small built-in table plus the caller's own.
/// An alias that would point at two different courses is dropped.
struct CourseAliasIndex: Sendable {
    struct Entry: Sendable, Hashable {
        var course: CourseID
        var priority: Int
    }

    static let priorityFull = 3
    static let priorityDerived = 2
    static let prioritySurname = 1

    private(set) var table: [String: Entry] = [:]
    private(set) var maxTokens = 1

    /// Built-in nicknames, keyed by a lowercase fragment of the course name.
    static let defaultNicknames: [(needle: String, aliases: [String])] = [
        ("organic chemistry", ["orgo", "ochem"]),
        ("linear algebra", ["linalg", "lin alg", "linear alg"]),
        ("macroeconomics", ["macro"]),
        ("microeconomics", ["micro"]),
        ("cell biology", ["cell bio"]),
        ("philosophy of mind", ["phil of mind"]),
        ("calculus", ["calc"]),
        ("statistics", ["stats"]),
        ("psychology", ["psych"]),
        ("computer science", ["cs"]),
    ]

    private static let nameStopWords: Set<String> = [
        "intro", "introduction", "advanced", "principles", "topics", "modern", "general",
    ]

    init(courses: [Course], extraAliases: [CourseID: [String]] = [:], useDefaultNicknames: Bool = true) {
        var ambiguous = Set<String>()
        var table: [String: Entry] = [:]

        func add(_ alias: String, _ course: CourseID, _ priority: Int) {
            let key = Self.tokens(alias).joined(separator: " ")
            guard !key.isEmpty, !ambiguous.contains(key) else { return }
            if let old = table[key] {
                if old.course != course {
                    table[key] = nil
                    ambiguous.insert(key)
                } else if priority > old.priority {
                    table[key] = Entry(course: course, priority: priority)
                }
            } else {
                table[key] = Entry(course: course, priority: priority)
            }
        }

        for course in courses {
            let id = course.id
            let name = Self.tokens(course.name)
            add(name.joined(separator: " "), id, Self.priorityFull)
            for w in name where w.count >= 5 && !Self.nameStopWords.contains(w) {
                add(w, id, Self.priorityDerived)
            }
            let code = Self.tokens(course.code)
            add(code.joined(separator: " "), id, Self.priorityFull)
            add(code.joined(), id, Self.priorityFull)
            if let first = code.first, first.contains(where: \.isLetter), !first.allSatisfy(\.isNumber) {
                let letters = String(first.prefix { $0.isLetter })
                if letters.count >= 2 { add(letters, id, Self.priorityDerived) }
            }
            if id.count >= 3 { add(id, id, Self.priorityDerived) }
            if let surname = course.professor.flatMap({ Self.tokens($0).last }), surname.count >= 4 {
                add(surname, id, Self.prioritySurname)
            }
            if useDefaultNicknames {
                let lowered = name.joined(separator: " ")
                for (needle, aliases) in Self.defaultNicknames where lowered.contains(needle) {
                    for a in aliases { add(a, id, Self.priorityDerived) }
                }
            }
            for a in extraAliases[id] ?? [] { add(a, id, Self.priorityFull) }
        }
        self.table = table
        self.maxTokens = max(1, table.keys.map { $0.split(separator: " ").count }.max() ?? 1)
    }

    /// Lowercase alphanumeric words of `text`.
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for c in text {
            if c.isLetter || c.isNumber { cur.append(contentsOf: c.lowercased()) }
            else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Longest alias that starts at `words[start]` (all words must be free per `isFree`).
    func match(words: [String], at start: Int, isFree: (Int) -> Bool) -> (length: Int, entry: Entry)? {
        var length = min(maxTokens, words.count - start)
        while length >= 1 {
            if (start..<(start + length)).allSatisfy(isFree),
               let e = table[words[start..<(start + length)].joined(separator: " ")] {
                return (length, e)
            }
            length -= 1
        }
        return nil
    }
}
