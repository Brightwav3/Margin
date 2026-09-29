/// A typed YAML value inside note frontmatter (`docs/plan/05-vault-spec.md` §2, §5, §6, §12).
///
/// Maps keep their key order (`[Pair]`), so nothing is reordered when a value is edited.
public enum FrontmatterValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case date(LocalDate)
    case dateTime(LocalDateTime)
    case list([FrontmatterValue])
    case map([Pair])

    /// One `key: value` pair of a map.
    public struct Pair: Sendable, Hashable {
        public var key: String
        public var value: FrontmatterValue
        public init(_ key: String, _ value: FrontmatterValue) {
            self.key = key
            self.value = value
        }
    }

    /// The text of a string value; dates, numbers and booleans are rendered tolerantly
    /// (`code: 201` still reads as `"201"`). `null`, lists and maps yield `nil`.
    public var stringValue: String? {
        switch self {
        case .string(let s): s
        case .number(let d): YAMLSubset.renderNumber(d)
        case .bool(let b): b ? "true" : "false"
        case .date(let d): d.iso
        case .dateTime(let d): d.iso
        case .null, .list, .map: nil
        }
    }

    public var numberValue: Double? {
        if case .number(let d) = self { return d }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// A date; a date-time yields its date, a quoted ISO string is accepted too.
    public var dateValue: LocalDate? {
        switch self {
        case .date(let d): d
        case .dateTime(let dt): dt.date
        case .string(let s): LocalDate(iso: s.trimmingSpaces())
        default: nil
        }
    }

    public var dateTimeValue: LocalDateTime? {
        switch self {
        case .dateTime(let dt): dt
        case .string(let s): LocalDateTime(iso: s.trimmingSpaces())
        default: nil
        }
    }

    public var listValue: [FrontmatterValue]? {
        if case .list(let l) = self { return l }
        return nil
    }

    public var mapValue: [Pair]? {
        if case .map(let m) = self { return m }
        return nil
    }

    /// First value for `key` when this is a map.
    public subscript(key: String) -> FrontmatterValue? {
        guard case .map(let pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }
}

extension FrontmatterValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral,
    ExpressibleByNilLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: FrontmatterValue...) { self = .list(elements) }
    public init(nilLiteral: ()) { self = .null }
}

extension String {
    fileprivate func trimmingSpaces() -> String {
        String(decoding: YAMLSubset.trim(Array(utf8)[...]), as: UTF8.self)
    }
}
