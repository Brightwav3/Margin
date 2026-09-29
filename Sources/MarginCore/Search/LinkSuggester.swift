import Foundation

/// A note a `[[` link can point at, as the suggester sees it.
public struct LinkTarget: Sendable, Hashable, Identifiable {
    public var id: NoteID
    public var courseID: CourseID?
    /// File name without `.md`; what a link contains (`[[name]]`).
    public var name: String
    /// Vault-relative path without `.md`; used to tell equal names apart.
    public var path: String
    public var title: String
    public var aliases: [String]
    public var headings: [String]

    public init(id: NoteID, courseID: CourseID? = nil, name: String, path: String? = nil, title: String? = nil,
                aliases: [String] = [], headings: [String] = []) {
        self.id = id; self.courseID = courseID; self.name = name; self.path = path ?? name
        self.title = title ?? name; self.aliases = aliases; self.headings = headings
    }
}

/// Suggestions for the text typed after `[[`: titles, file names and aliases (ranked, notes of the
/// same course first), headings after `#`, and a "create" entry when the name is new.
///
/// Rules:
/// - A match is a title, file name or alias that equals, starts with, has a word starting with, or
///   contains the typed text (case and diacritics ignored). Loose letter-order matches are not
///   suggested; the popup is for links, not for the command palette.
/// - Ranking: match quality, plus a bonus for the course of the note being edited, an alias
///   counting slightly less than a title; ties by title, then id.
/// - `Note#text` lists the headings of the best matching notes, `#text` those of the current note.
///   `text|` (a display alias being typed) has no suggestions.
/// - The current note is never suggested as a plain link target.
/// - `.create` comes last, only when text was typed, no `#`/`|` is in it, and no note has that
///   exact name or title.
///
/// Building a suggester folds every name once; `suggest` then touches strings only for the
/// notes that pass a cheap prefilter (budget 20 ms for 1000 notes).
public struct LinkSuggester: Sendable {
    private struct Entry: Sendable {
        var target: LinkTarget
        var foldedName: String
        var foldedTitle: String
        var foldedAliases: [String]
        /// Title, file name and aliases joined; a match of any of them needs the first typed word
        /// to occur in here, which rejects most notes without scoring them.
        var haystack: String
        /// `name`, or `folder/name` when another note has the same name.
        var linkText: String
    }

    static let sameCourseBonus = 100
    static let aliasPenalty = 20
    static let minimumScore = 400
    /// Headings are offered for at most this many notes of `Note#`.
    static let headingNotes = 3

    private let entries: [Entry]
    private let byID: [NoteID: Int]

    public init(targets: [LinkTarget]) {
        var nameCount: [String: Int] = [:]
        for t in targets { nameCount[SearchTokenizer.fold(t.name), default: 0] += 1 }
        var list: [Entry] = []
        list.reserveCapacity(targets.count)
        for t in targets {
            let folded = SearchTokenizer.fold(t.name)
            var linkText = t.name
            if nameCount[folded, default: 0] > 1 {
                let parts = t.path.split(separator: "/")
                if parts.count >= 2 { linkText = "\(parts[parts.count - 2])/\(t.name)" }
            }
            list.append(Entry(target: t, foldedName: Self.fold(t.name), foldedTitle: Self.fold(t.title),
                              foldedAliases: t.aliases.map(Self.fold), haystack: "", linkText: linkText))
            list[list.count - 1].haystack = ([list[list.count - 1].foldedTitle, list[list.count - 1].foldedName]
                + list[list.count - 1].foldedAliases).joined(separator: "\n")
        }
        entries = list.sorted { ($0.target.title.lowercased(), $0.target.id) < ($1.target.title.lowercased(), $1.target.id) }
        var index: [NoteID: Int] = [:]
        for (i, e) in entries.enumerated() where index[e.target.id] == nil { index[e.target.id] = i }
        byID = index
    }

    /// - Parameters:
    ///   - text: what follows `[[`.
    ///   - course: the course of the note being edited (its notes come first).
    ///   - note: the note being edited (excluded; `#text` refers to it).
    public func suggest(_ text: String, course: CourseID? = nil, note: NoteID? = nil,
                        limit: Int = 8) -> [LinkSuggestion] {
        guard limit > 0, !text.contains("|") else { return [] }
        let raw = text.trimmingCharacters(in: .whitespaces)
        if let hash = raw.firstIndex(of: "#") {
            return headingSuggestions(notePart: String(raw[..<hash]),
                                      headingPart: String(raw[raw.index(after: hash)...]),
                                      course: course, note: note, limit: limit)
        }
        let q = Self.fold(raw)
        let firstWord = Self.firstWord(of: q)
        var ranked: [(score: Int, entry: Entry, alias: String?)] = []
        for e in entries where e.target.id != note {
            let bonus = course != nil && e.target.courseID == course ? Self.sameCourseBonus : 0
            if q.isEmpty { ranked.append((bonus, e, nil)); continue }
            if let first = firstWord, !e.haystack.contains(first) { continue }
            var best = max(Self.match(q, e.foldedTitle) ?? -1, Self.match(q, e.foldedName) ?? -1)
            var alias: String?
            for (i, a) in e.foldedAliases.enumerated() {
                if let s = Self.match(q, a), s - Self.aliasPenalty > best { best = s - Self.aliasPenalty; alias = e.target.aliases[i] }
            }
            if best >= Self.minimumScore { ranked.append((best + bonus, e, alias)) }
        }
        // `entries` is already ordered by title, so a stable sort by score keeps the tie-break.
        let sorted = ranked.enumerated().sorted {
            $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset
        }.map(\.element)

        let wantsCreate = !q.isEmpty && !entries.contains { $0.foldedName == q || $0.foldedTitle == q }
        var out: [LinkSuggestion] = []
        for r in sorted.prefix(max(0, limit - (wantsCreate ? 1 : 0))) {
            let t = r.entry.target
            if let alias = r.alias {
                out.append(LinkSuggestion(id: "alias:\(t.id):\(alias)", kind: .alias, title: alias,
                                          insertText: "\(r.entry.linkText)|\(alias)", noteID: t.id,
                                          courseID: t.courseID, detail: t.title))
            } else {
                out.append(LinkSuggestion(id: "note:\(t.id)", kind: .note, title: t.title,
                                          insertText: r.entry.linkText, noteID: t.id, courseID: t.courseID))
            }
        }
        if wantsCreate {
            out.append(LinkSuggestion(id: "create:\(raw)", kind: .create, title: raw, insertText: raw,
                                      courseID: course))
        }
        return out
    }

    private func headingSuggestions(notePart: String, headingPart: String, course: CourseID?, note: NoteID?,
                                    limit: Int) -> [LinkSuggestion] {
        let n = Self.fold(notePart.trimmingCharacters(in: .whitespaces))
        let h = Self.fold(headingPart)
        var sources: [(entry: Entry, current: Bool)] = []
        if n.isEmpty {
            if let note, let i = byID[note] { sources = [(entries[i], true)] }
        } else {
            var ranked: [(Int, Entry)] = []
            let firstWord = Self.firstWord(of: n)
            for e in entries {
                if let firstWord, !e.haystack.contains(firstWord) { continue }
                let bonus = course != nil && e.target.courseID == course ? Self.sameCourseBonus : 0
                let s = max(Self.match(n, e.foldedTitle) ?? -1, Self.match(n, e.foldedName) ?? -1)
                if s >= Self.minimumScore { ranked.append((s + bonus, e)) }
            }
            ranked = ranked.enumerated().sorted {
                $0.element.0 != $1.element.0 ? $0.element.0 > $1.element.0 : $0.offset < $1.offset
            }.map(\.element)
            sources = ranked.prefix(Self.headingNotes).map { ($0.1, false) }
        }
        var out: [LinkSuggestion] = []
        for (e, current) in sources {
            for heading in e.target.headings {
                let f = Self.fold(heading)
                if !h.isEmpty && (Self.match(h, f) ?? -1) < Self.minimumScore { continue }
                let t = e.target
                out.append(LinkSuggestion(
                    id: "heading:\(t.id):\(heading)", kind: .heading, title: heading,
                    insertText: current ? "#\(heading)" : "\(e.linkText)#\(heading)",
                    noteID: t.id, courseID: t.courseID, detail: t.title))
                if out.count >= limit { return out }
            }
        }
        return out
    }

    private static func firstWord(of folded: String) -> String? {
        folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init)
    }

    private static func fold(_ s: String) -> String { CommandRegistry.fold(s) }

    private static func match(_ q: String, _ text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        return CommandRegistry.score(q, in: text)
    }
}
