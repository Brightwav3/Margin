import Foundation

/// Any JSON value. Lets the settings file keep keys the app does not know.
enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// The content of `.margin/settings.json`: a flat JSON object of setting keys. Shared by the fixture
/// (memory) and the vault (file) implementations of `SettingsStore`.
struct SettingsDocument: Sendable, Equatable {
    private(set) var values: [String: JSONValue] = [:]

    init() {}

    /// Parses the file text. Empty text is an empty document; anything but a JSON object is `.invalid`.
    init(parsing text: String?) throws {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do { values = try JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8)) }
        catch { throw MarginError.invalid("settings.json is not a JSON object, not touching it: \(error)") }
    }

    func value<Value: Codable & Sendable>(for setting: Setting<Value>) -> Value {
        guard let stored = values[setting.key], let decoded = try? Self.decode(Value.self, from: stored) else {
            return setting.defaultValue
        }
        return decoded
    }

    /// Stores `value`; returns `false` when it is already what is stored.
    mutating func set<Value: Codable & Sendable>(_ setting: Setting<Value>, _ value: Value) throws -> Bool {
        let json = try Self.encode(value)
        guard values[setting.key] != json else { return false }
        values[setting.key] = json
        return true
    }

    /// Removes the key; returns `false` when it was not there.
    mutating func remove(key: String) -> Bool { values.removeValue(forKey: key) != nil }

    func render() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: (try? encoder.encode(values)) ?? Data("{}".utf8), as: UTF8.self) + "\n"
    }

    // Values are wrapped in an array so that scalars (a bare `true`) encode on every Foundation.
    private static func encode<Value: Encodable>(_ value: Value) throws -> JSONValue {
        do {
            let data = try JSONEncoder().encode([value])
            guard case .array(let items)? = try? JSONDecoder().decode(JSONValue.self, from: data), let first = items.first else {
                throw MarginError.invalid("Setting value cannot be stored")
            }
            return first
        } catch let e as MarginError { throw e } catch { throw MarginError.invalid("Setting value cannot be stored: \(error)") }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from json: JSONValue) throws -> Value {
        let data = try JSONEncoder().encode([json])
        return try JSONDecoder().decode([Value].self, from: data)[0]
    }
}
