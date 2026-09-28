import Foundation

/// Source of randomness for `StableIDGenerator`. Production uses `SystemIDRandomSource`; tests
/// inject a seeded generator so ids are reproducible.
public protocol IDRandomSource: Sendable {
    mutating func next() -> UInt64
}

/// The operating system's random number generator.
public struct SystemIDRandomSource: IDRandomSource {
    public init() {}
    public mutating func next() -> UInt64 {
        var generator = SystemRandomNumberGenerator()
        return generator.next()
    }
}

/// What an id identifies.
public enum StableIDKind: Sendable, Hashable, CaseIterable {
    case note
    case task

    /// `n-` for notes, `t-` for tasks.
    public var prefix: String {
        switch self {
        case .note: "n-"
        case .task: "t-"
        }
    }
}

/// Generates short stable ids: `n-9c1e` for notes, `t-4f2a` for tasks (D-012).
///
/// An id is the kind's prefix plus 4 to 6 characters of a lowercase base32 alphabet
/// (`0-9a-z` without `i l o u`). Letters, digits and `-` only, so a task id is a valid Obsidian
/// block id. Candidates are drawn with the injected `IDRandomSource` and checked against the set of
/// ids that are already in use; on a collision the generator retries and then lengthens the id,
/// so it always terminates and never returns an id from the set.
public struct StableIDGenerator: Sendable {
    /// The 32 characters ids are made of.
    public static let alphabet: [Character] = Array("0123456789abcdefghjkmnpqrstvwxyz")

    /// Shortest and longest id body a normal id has (without the prefix).
    public static let bodyLengths = 4...6

    private static let attemptsPerLength = 32
    private static let extendedMaxLength = 12

    private var source: any IDRandomSource
    private let startLength: Int

    /// - Parameter length: body length to try first, clamped to 4...6. Longer bodies are used only
    ///   when shorter ones keep colliding.
    public init(source: any IDRandomSource = SystemIDRandomSource(), length: Int = 4) {
        self.source = source
        self.startLength = min(max(length, Self.bodyLengths.lowerBound), Self.bodyLengths.upperBound)
    }

    /// A new id of `kind` that is not in `existing`.
    public mutating func next(_ kind: StableIDKind, avoiding existing: Set<String> = []) -> String {
        var length = startLength
        while length <= Self.extendedMaxLength {
            for _ in 0..<Self.attemptsPerLength {
                let candidate = kind.prefix + randomBody(length: length)
                if !existing.contains(candidate) { return candidate }
            }
            length += 1
        }
        // Deterministic fallback (only reachable with a degenerate random source): terminates
        // because `existing` is finite.
        let base = kind.prefix + randomBody(length: Self.bodyLengths.upperBound)
        var counter = 1
        while existing.contains("\(base)-\(counter)") { counter += 1 }
        return "\(base)-\(counter)"
    }

    private mutating func randomBody(length: Int) -> String {
        var bits = source.next()
        var drawn = 0
        var out = ""
        out.reserveCapacity(length)
        for _ in 0..<length {
            if drawn == 12 { bits = source.next(); drawn = 0 }
            out.append(Self.alphabet[Int(bits & 31)])
            bits >>= 5
            drawn += 1
        }
        return out
    }

    /// `true` when `id` has the shape this generator produces for `kind`.
    public static func isGenerated(_ id: String, kind: StableIDKind) -> Bool {
        guard id.hasPrefix(kind.prefix) else { return false }
        let body = id.dropFirst(kind.prefix.count)
        return bodyLengths.contains(body.count) && body.allSatisfy { alphabet.contains($0) }
    }

    /// `true` for the location-derived placeholder ids that predate stable ids
    /// (`<noteID>#L<line>` for tasks).
    public static func isPlaceholderTaskID(_ id: String) -> Bool {
        guard let r = id.range(of: "#L", options: .backwards) else { return false }
        let digits = id[r.upperBound...]
        return !digits.isEmpty && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber)
    }
}
