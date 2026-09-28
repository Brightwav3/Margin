import Foundation

/// Typed accessors for the known note keys (`docs/plan/05-vault-spec.md` §2, §12).
/// Reading is tolerant; assigning `nil` (or an empty tag list) removes the key.
extension Frontmatter {
    /// `date:` as `LocalDate` (a date-time or quoted ISO string is accepted).
    public var date: LocalDate? {
        get { value(for: "date")?.dateValue }
        set { assign("date", newValue.map { .date($0) }) }
    }

    /// `class:` as a bare course name. Accepts `Cell Biology`, `"[[Cell Biology]]"`, an unquoted
    /// `[[Cell Biology]]` (YAML reads it as nested lists) and `[[Cell Biology|Bio]]`.
    /// Assigning writes the canonical `"[[Name]]"`.
    public var className: String? {
        get {
            guard let v = value(for: "class") else { return nil }
            return Self.courseName(v)
        }
        set { assign("class", newValue.map { .string("[[\($0)]]") }) }
    }

    /// `type:` (unknown values yield `nil`; the raw text stays in the file).
    public var kind: NoteKind? {
        get {
            guard let s = string(for: "type") else { return nil }
            return NoteKind(rawValue: s.lowercased())
        }
        set { assign("type", newValue.map { .string($0.rawValue) }) }
    }

    /// `session:` link to a timetable slot (`2026-09-24T10:00`).
    public var session: LocalDateTime? {
        get { value(for: "session")?.dateTimeValue }
        set { assign("session", newValue.map { .dateTime($0) }) }
    }

    /// `tags:` as a block/flow list or a comma/space separated string; leading `#` is dropped.
    public var tags: [String] {
        get {
            guard let v = value(for: "tags") else { return [] }
            let raw: [String]
            switch v {
            case .list(let items): raw = items.compactMap(\.stringValue)
            case .string(let s): raw = s.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            default: raw = []
            }
            return raw.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }.filter { !$0.isEmpty }
        }
        set { assign("tags", newValue.isEmpty ? nil : .list(newValue.map { .string($0) })) }
    }

    /// `due:`
    public var due: LocalDate? {
        get { value(for: "due")?.dateValue }
        set { assign("due", newValue.map { .date($0) }) }
    }

    /// `weight:` in percent (`25%` and `25` both read as `25`). Assigning writes `25%`.
    public var weight: Double? {
        get {
            switch value(for: "weight") {
            case .number(let d)?: return d
            case .string(let s)?:
                let t = s.hasSuffix("%") ? String(s.dropLast()) : s
                return Double(t.trimmingCharacters(in: .whitespaces))
            default: return nil
            }
        }
        set { assign("weight", newValue.map { .string("\(YAMLSubset.renderNumber($0))%") }) }
    }

    /// `id:` stable note id (`n-9c1e`).
    public var id: String? {
        get { string(for: "id") }
        set { assign("id", newValue.map { .string($0) }) }
    }

    private mutating func assign(_ key: String, _ value: FrontmatterValue?) {
        if let value { set(key, value) } else { remove(key) }
    }

    private static func courseName(_ v: FrontmatterValue) -> String? {
        var v = v
        while case .list(let items) = v, items.count == 1 { v = items[0] }
        guard var s = v.stringValue else { return nil }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[["), s.hasSuffix("]]"), s.count >= 4 { s = String(s.dropFirst(2).dropLast(2)) }
        if let bar = s.firstIndex(of: "|") { s = String(s[..<bar]) }
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }
}
