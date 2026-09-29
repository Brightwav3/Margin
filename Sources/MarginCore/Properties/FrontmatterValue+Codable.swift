/// JSON shape of a `FrontmatterValue` at the API boundary: `{"kind": "...", "value": ...}`.
///
/// Dates are ISO strings (`2026-10-01`, `2026-10-01T10:00`); a map is a list of
/// `{"key": ..., "value": ...}` pairs so key order survives the round trip.
extension FrontmatterValue: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "null": self = .null
        case "bool": self = .bool(try c.decode(Bool.self, forKey: .value))
        case "number": self = .number(try c.decode(Double.self, forKey: .value))
        case "string": self = .string(try c.decode(String.self, forKey: .value))
        case "date":
            let s = try c.decode(String.self, forKey: .value)
            guard let d = LocalDate(iso: s) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: c, debugDescription: "Bad date '\(s)'")
            }
            self = .date(d)
        case "dateTime":
            let s = try c.decode(String.self, forKey: .value)
            guard let d = LocalDateTime(iso: s) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: c, debugDescription: "Bad date-time '\(s)'")
            }
            self = .dateTime(d)
        case "list": self = .list(try c.decode([FrontmatterValue].self, forKey: .value))
        case "map": self = .map(try c.decode([Pair].self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown value kind '\(kind)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null: try c.encode("null", forKey: .kind)
        case .bool(let b): try c.encode("bool", forKey: .kind); try c.encode(b, forKey: .value)
        case .number(let d): try c.encode("number", forKey: .kind); try c.encode(d, forKey: .value)
        case .string(let s): try c.encode("string", forKey: .kind); try c.encode(s, forKey: .value)
        case .date(let d): try c.encode("date", forKey: .kind); try c.encode(d.iso, forKey: .value)
        case .dateTime(let d): try c.encode("dateTime", forKey: .kind); try c.encode(d.iso, forKey: .value)
        case .list(let l): try c.encode("list", forKey: .kind); try c.encode(l, forKey: .value)
        case .map(let m): try c.encode("map", forKey: .kind); try c.encode(m, forKey: .value)
        }
    }
}

extension FrontmatterValue.Pair: Codable {
    private enum CodingKeys: String, CodingKey { case key, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decode(String.self, forKey: .key), try c.decode(FrontmatterValue.self, forKey: .value))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(value, forKey: .value)
    }
}
