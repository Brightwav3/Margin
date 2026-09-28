import Foundation

/// A command of the command palette. Plain data: the app binds `id` to an action.
public struct Command: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var keywords: [String]
    /// Section heading in the palette (`Navigate`, `Create`, ...).
    public var group: String
    /// Display string of the shortcut (`⌘N`), `nil` when there is none.
    public var shortcut: String?

    public init(id: String, title: String, keywords: [String] = [], group: String, shortcut: String? = nil) {
        self.id = id; self.title = title; self.keywords = keywords; self.group = group; self.shortcut = shortcut
    }
}

/// Recently used commands, injected so ranking stays pure and testable.
public protocol CommandHistory: Sendable {
    /// Command ids, most recent first.
    var recentIDs: [String] { get }
}

public struct StaticCommandHistory: CommandHistory, Hashable {
    public var recentIDs: [String]
    public init(recentIDs: [String] = []) { self.recentIDs = recentIDs }
}

/// One search result.
public struct RankedCommand: Sendable, Hashable, Identifiable {
    public var id: String { command.id }
    public var command: Command
    public var score: Int
}

/// Holds the commands and ranks them for a query.
///
/// Ranking (higher first): exact title 1000 > title prefix 800...900 > title word-start
/// (every query token starts a title word) 600...700 > substring 400 > subsequence 200...250.
/// Keyword matches use the same tiers scaled by 0.75 and capped at 590, so a title word-start match or better always wins. Comparison ignores
/// case and diacritics. Recency adds up to 60 points (most recent first, 6 fewer per rank), which
/// reorders results inside a tier but never lifts a result over a better tier. Ties: shorter title,
/// then title, then id. An empty query lists recent commands first, then the rest alphabetically.
public struct CommandRegistry: Sendable {
    public private(set) var commands: [Command] = []

    public static let maxRecencyBoost = 60

    public init(commands: [Command] = []) {
        for c in commands { _ = try? register(c) }
    }

    /// Adds a command; duplicate ids throw `.invalid`.
    public mutating func register(_ command: Command) throws(MarginError) {
        guard !commands.contains(where: { $0.id == command.id }) else {
            throw .invalid("duplicate command id: \(command.id)")
        }
        commands.append(command)
    }

    public func command(id: String) -> Command? { commands.first { $0.id == id } }

    public func search(_ query: String, history: some CommandHistory = StaticCommandHistory(), limit: Int = 50)
        -> [RankedCommand]
    {
        let rank = Dictionary(history.recentIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func boost(_ id: String) -> Int { rank[id].map { max(0, Self.maxRecencyBoost - 6 * $0) } ?? 0 }

        let q = Self.fold(query)
        var out: [RankedCommand] = []
        for c in commands {
            if q.isEmpty {
                out.append(RankedCommand(command: c, score: boost(c.id)))
                continue
            }
            var best = Self.score(q, in: Self.fold(c.title))
            for k in c.keywords {
                if let s = Self.score(q, in: Self.fold(k)) { best = max(best ?? 0, min(s * 3 / 4, 590)) }
            }
            if let best { out.append(RankedCommand(command: c, score: best + boost(c.id))) }
        }
        out.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.command.title.count != $1.command.title.count { return $0.command.title.count < $1.command.title.count }
            if $0.command.title != $1.command.title { return $0.command.title < $1.command.title }
            return $0.command.id < $1.command.id
        }
        return Array(out.prefix(max(0, limit)))
    }

    // MARK: matching

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func words(_ s: String) -> [Substring] {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    /// Score of folded `q` against folded `text`, `nil` when it does not match.
    static func score(_ q: String, in text: String) -> Int? {
        if text == q { return 1000 }
        if text.hasPrefix(q) { return max(800, 900 - (text.count - q.count)) }
        let tokens = words(q)
        let tw = words(text)
        if !tokens.isEmpty {
            var used = Set<Int>(), firstIdx = Int.max, all = true
            for t in tokens {
                if let i = tw.indices.first(where: { !used.contains($0) && tw[$0].hasPrefix(t) }) {
                    used.insert(i); firstIdx = min(firstIdx, i)
                } else { all = false; break }
            }
            if all { return 700 - min(firstIdx, 20) * 5 }
        }
        if text.contains(q) { return 400 }
        // subsequence: characters in order; tighter spans score higher
        var idx = text.startIndex, first: String.Index?, last = text.startIndex
        for ch in q where ch != " " {
            guard let f = text[idx...].firstIndex(of: ch) else { return nil }
            if first == nil { first = f }
            last = f; idx = text.index(after: f)
        }
        guard let first else { return nil }
        let span = text.distance(from: first, to: last) + 1
        let n = q.filter { $0 != " " }.count
        return 200 + max(0, 50 - (span - n) * 5)
    }
}
