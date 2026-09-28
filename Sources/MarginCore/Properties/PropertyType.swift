import Foundation

/// The value types offered by "Add property" (mockup 1e) plus `list` and `link`.
public enum PropertyType: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case date, text, tags, number, checkbox, list, link

    public var id: String { rawValue }

    /// English label for pickers (the UI localises).
    public var displayName: String {
        switch self {
        case .date: "Date"
        case .text: "Text"
        case .tags: "Tags"
        case .number: "Number"
        case .checkbox: "Checkbox"
        case .list: "List"
        case .link: "Link"
        }
    }

    /// The value a new property of this type starts with.
    public var defaultValue: FrontmatterValue {
        switch self {
        case .date, .text, .link: .string("")
        case .tags, .list: .list([])
        case .number: .number(0)
        case .checkbox: .bool(false)
        }
    }

    /// Checks `value` against this type and returns it in canonical form:
    /// - `date`: `.date`, `.dateTime` (date part) or an ISO string -> `.date`
    /// - `text`: string; numbers and booleans are rendered as text
    /// - `tags`: list of strings or a comma/space separated string; `#` dropped, duplicates
    ///   removed (order kept), empty entries dropped
    /// - `number`: finite number or numeric string
    /// - `checkbox`: bool or `"true"`/`"false"`
    /// - `list`: list of scalars (no nested lists or maps)
    /// - `link`: `[[Note]]` / `[[Note|alias]]`; plain non-empty text is wrapped as `[[text]]`
    public func validate(_ value: FrontmatterValue) throws(PropertyValidationError) -> FrontmatterValue {
        if case .null = value { throw .missingValue(self) }
        switch self {
        case .date:
            switch value {
            case .list, .map, .bool, .number: throw mismatch(value)
            default: break
            }
            if let d = value.dateValue { return .date(d) }
            throw .invalidDate(value.stringValue ?? "")
        case .text:
            guard let s = value.stringValue else { throw mismatch(value) }
            return .string(s)
        case .tags:
            let raw: [String]
            switch value {
            case .list(let items):
                raw = try items.map { item throws(PropertyValidationError) in
                    guard case .string(let s) = item else { throw .invalidElement(self, item.kindName) }
                    return s
                }
            case .string(let s): raw = s.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            default: throw mismatch(value)
            }
            var seen = Set<String>(), out: [FrontmatterValue] = []
            for t in raw {
                var tag = t.trimmingCharacters(in: .whitespaces)
                if tag.hasPrefix("#") { tag.removeFirst() }
                if !tag.isEmpty, seen.insert(tag).inserted { out.append(.string(tag)) }
            }
            return .list(out)
        case .number:
            switch value {
            case .number(let d):
                guard d.isFinite else { throw .invalidNumber(String(d)) }
                return .number(d)
            case .string(let s):
                let t = s.trimmingCharacters(in: .whitespaces)
                guard let d = Double(t), d.isFinite else { throw .invalidNumber(s) }
                return .number(d)
            default: throw mismatch(value)
            }
        case .checkbox:
            switch value {
            case .bool: return value
            case .string(let s):
                switch s.trimmingCharacters(in: .whitespaces).lowercased() {
                case "true": return .bool(true)
                case "false": return .bool(false)
                default: throw mismatch(value)
                }
            default: throw mismatch(value)
            }
        case .list:
            guard case .list(let items) = value else { throw mismatch(value) }
            for item in items {
                switch item {
                case .list, .map: throw .invalidElement(self, item.kindName)
                default: break
                }
            }
            return value
        case .link:
            guard case .string(let s) = value else { throw mismatch(value) }
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[["), t.hasSuffix("]]"), t.count > 4 {
                let inner = t.dropFirst(2).dropLast(2)
                guard !inner.contains("[") && !inner.contains("]"),
                      !inner.trimmingCharacters(in: .whitespaces).isEmpty
                else { throw .invalidLink(s) }
                return .string(t)
            }
            guard !t.isEmpty, !t.contains("[") , !t.contains("]") else { throw .invalidLink(s) }
            return .string("[[\(t)]]")
        }
    }

    /// The type that best describes an existing value (for keys without a registered type).
    public static func infer(from value: FrontmatterValue) -> PropertyType {
        switch value {
        case .bool: .checkbox
        case .number: .number
        case .date, .dateTime: .date
        case .list(let items): items.allSatisfy { if case .string = $0 { true } else { false } } ? .tags : .list
        case .null, .string, .map: .text
        }
    }

    private func mismatch(_ v: FrontmatterValue) -> PropertyValidationError {
        .typeMismatch(expected: self, found: v.kindName)
    }
}

/// Why a value was rejected for a `PropertyType`.
public enum PropertyValidationError: Error, Sendable, Hashable {
    case missingValue(PropertyType)
    case typeMismatch(expected: PropertyType, found: String)
    case invalidDate(String)
    case invalidNumber(String)
    case invalidLink(String)
    case invalidElement(PropertyType, String)
    case invalidKey(String)
    case conflictingType(key: String, registered: PropertyType, requested: PropertyType)

    public var marginError: MarginError { .invalid(description) }
}

extension PropertyValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingValue(let t): "\(t.rawValue) property needs a value"
        case .typeMismatch(let t, let f): "expected \(t.rawValue), found \(f)"
        case .invalidDate(let s): "not a valid date (YYYY-MM-DD): \(s)"
        case .invalidNumber(let s): "not a valid number: \(s)"
        case .invalidLink(let s): "not a valid [[link]]: \(s)"
        case .invalidElement(let t, let f): "\(t.rawValue) cannot contain \(f)"
        case .invalidKey(let k): "invalid property key: \(k)"
        case .conflictingType(let k, let r, let q): "property \(k) is \(r.rawValue), not \(q.rawValue)"
        }
    }
}

extension FrontmatterValue {
    /// Short kind name for error messages.
    var kindName: String {
        switch self {
        case .null: "null"
        case .bool: "checkbox"
        case .number: "number"
        case .string: "text"
        case .date: "date"
        case .dateTime: "date-time"
        case .list: "list"
        case .map: "map"
        }
    }
}

/// Maps property keys to types. Built-in keys of `docs/plan/05-vault-spec.md` are pre-registered;
/// custom keys are registered at runtime by the caller (e.g. from the vault) and stay immutable
/// value data here.
public struct PropertyRegistry: Sendable, Hashable {
    public private(set) var types: [String: PropertyType]

    public static let builtIn: PropertyRegistry = PropertyRegistry(types: [
        "date": .date, "due": .date, "tags": .tags, "class": .link,
        "weight": .number, "type": .text,
    ])

    public init(types: [String: PropertyType] = [:]) { self.types = types }

    /// Keys are non-empty, have no newline, colon, leading `#`/`-`/`[`/`{` or surrounding spaces.
    public static func validateKey(_ key: String) throws(PropertyValidationError) {
        guard let first = key.first, key == key.trimmingCharacters(in: .whitespaces),
              !"#-[]{}&*!|>'\"%@`".contains(first),
              !key.contains(":"), !key.contains("\n"), !key.contains("\r")
        else { throw .invalidKey(key) }
    }

    public func type(for key: String) -> PropertyType? { types[key.lowercased()] }

    /// Registers `key` (case-insensitive). Re-registering with a different type fails.
    public mutating func register(key: String, type: PropertyType) throws(PropertyValidationError) {
        try Self.validateKey(key)
        let k = key.lowercased()
        if let existing = types[k], existing != type {
            throw .conflictingType(key: key, registered: existing, requested: type)
        }
        types[k] = type
    }

    /// Validates `value` for `key`: uses the registered type, else infers one from the value.
    public func validate(key: String, value: FrontmatterValue) throws(PropertyValidationError) -> FrontmatterValue {
        try Self.validateKey(key)
        return try (type(for: key) ?? PropertyType.infer(from: value)).validate(value)
    }
}
