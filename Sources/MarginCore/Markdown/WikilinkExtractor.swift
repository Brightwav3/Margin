import Foundation

/// A parsed `[[wikilink]]` or `![[embed]]`.
///
/// Forms: `[[Note]]`, `[[Note|alias]]`, `[[Note#Heading]]`, `[[Note#^block]]`,
/// `[[Folder/Note]]`, `[[#Heading]]` (link to the same note; `target` is empty).
public struct Wikilink: Sendable, Hashable {
    /// Note part without heading, alias and a trailing `.md`, trimmed. Empty for `[[#Heading]]`.
    public var target: String
    /// Text after `#` (without a `^` block marker).
    public var heading: String?
    /// Block id after `#^`.
    public var blockID: String?
    /// Text after `|` (display alias; for embeds often a size such as `200`).
    public var alias: String?
    public var isEmbed: Bool
    /// 1-based line.
    public var line: Int
    /// Byte range of the whole link in the source text.
    public var range: ByteRange

    /// Folder part of `Folder/Note`, `nil` for a bare name.
    public var folder: String? {
        guard let slash = target.lastIndex(of: "/") else { return nil }
        return String(target[..<slash])
    }

    /// Last path component.
    public var name: String {
        guard let slash = target.lastIndex(of: "/") else { return target }
        return String(target[target.index(after: slash)...])
    }

    /// Whether the link points at its own note (`[[#Heading]]`).
    public var isSelfLink: Bool { target.isEmpty }
}

/// A note known to the resolver.
public struct NoteRef: Sendable, Hashable, Identifiable {
    public var id: NoteID
    public var courseID: CourseID?
    /// File name without extension (`Glossary`); matched by bare `[[Glossary]]` links.
    public var name: String
    /// Vault-relative path without extension (`bio/Cell Biology/Glossary`); matched by suffix for
    /// links with a folder. Defaults to `name`.
    public var path: String

    public init(id: NoteID, courseID: CourseID? = nil, name: String, path: String? = nil) {
        self.id = id; self.courseID = courseID; self.name = name; self.path = path ?? name
    }
}

/// Outcome of resolving a wikilink.
public enum WikilinkResolution: Sendable, Hashable {
    case resolved(NoteID)
    /// Several equally good targets; the UI asks the user (vault spec §4). Sorted by id.
    case ambiguous([NoteID])
    /// No such note yet: a valid link shown as "Not created yet".
    case notCreated(target: String)
    /// `[[#Heading]]`: the note the link is in.
    case selfLink
}

/// A note text handed to backlink search.
public struct NoteSource: Sendable, Hashable {
    public var ref: NoteRef
    public var text: String

    public init(ref: NoteRef, text: String) { self.ref = ref; self.text = text }
}

/// A link to a note, with the line it stands on.
public struct Backlink: Sendable, Hashable {
    public var sourceNoteID: NoteID
    public var link: Wikilink
    public var line: Int
    /// The whole source line, trimmed, at most 160 characters (`…` appended when cut).
    public var snippet: String
}

/// Extracts and resolves wikilinks. Links inside code blocks and inline code are ignored (they
/// never reach this type: the scanner drops them).
public struct WikilinkExtractor: Sendable {
    public static let maxSnippetLength = 160
    private let scanner = MarkdownScanner()

    public init() {}

    public func extract(from text: String) -> [Wikilink] {
        extract(from: scanner.scan(text))
    }

    public func extract(from scan: MarkdownScan) -> [Wikilink] {
        scan.links.compactMap { link in
            link.kind == .wikilink ? Self.parse(inner: link.inner, isEmbed: link.isEmbed,
                                                 line: link.line, range: link.range) : nil
        }
    }

    static func parse(inner: String, isEmbed: Bool, line: Int, range: ByteRange) -> Wikilink? {
        var left = Substring(inner)
        var alias: String?
        if let bar = left.firstIndex(of: "|") {
            let a = left[left.index(after: bar)...].trimmingCharacters()
            alias = a.isEmpty ? nil : a
            left = left[..<bar]
            if left.last == "\\" { left = left.dropLast() }   // `\|` inside tables
        }
        var heading: String?
        var blockID: String?
        if let hash = left.firstIndex(of: "#") {
            var h = left[left.index(after: hash)...].trimmingCharacters()
            left = left[..<hash]
            if h.hasPrefix("^") {
                h.removeFirst()
                blockID = h.isEmpty ? nil : h
            } else {
                heading = h.isEmpty ? nil : h
            }
        }
        var target = left.trimmingCharacters()
        if target.lowercased().hasSuffix(".md") { target = String(target.dropLast(3)) }
        if target.isEmpty && heading == nil && blockID == nil { return nil }
        return Wikilink(target: target, heading: heading, blockID: blockID, alias: alias,
                        isEmbed: isEmbed, line: line, range: range)
    }

    // MARK: Resolution

    /// Resolves `link` written in a note of `sourceCourse`.
    ///
    /// Matching is case-insensitive and Unicode-normalised. A bare name matches the file name; a
    /// name with folders matches the end of the note path. Candidates from the source course win
    /// over the rest of the vault; more than one candidate at the winning level is ambiguous.
    public func resolve(_ link: Wikilink, from sourceCourse: CourseID?, in notes: [NoteRef]) -> WikilinkResolution {
        if link.isSelfLink { return .selfLink }
        let wanted = Self.normalise(link.target)
        let candidates: [NoteRef]
        if link.target.contains("/") {
            let suffix = "/" + wanted
            candidates = notes.filter {
                let p = Self.normalise($0.path)
                return p == wanted || p.hasSuffix(suffix)
            }
        } else {
            candidates = notes.filter { Self.normalise($0.name) == wanted }
        }
        var pool = candidates
        if let course = sourceCourse {
            let same = candidates.filter { $0.courseID == course }
            if !same.isEmpty { pool = same }
        }
        switch pool.count {
        case 0: return .notCreated(target: link.target)
        case 1: return .resolved(pool[0].id)
        default: return .ambiguous(pool.map(\.id).sorted())
        }
    }

    /// Notes that link to `noteID`, with the source line as context. Ambiguous links count for
    /// every candidate. Links from a note to itself are skipped.
    public func backlinks(to noteID: NoteID, in sources: [NoteSource]) -> [Backlink] {
        let refs = sources.map(\.ref)
        var result: [Backlink] = []
        for source in sources where source.ref.id != noteID {
            let lines = Self.splitLines(source.text)
            for link in extract(from: source.text) {
                let hit: Bool
                switch resolve(link, from: source.ref.courseID, in: refs) {
                case .resolved(let id): hit = id == noteID
                case .ambiguous(let ids): hit = ids.contains(noteID)
                case .notCreated, .selfLink: hit = false
                }
                guard hit else { continue }
                let raw = link.line - 1 < lines.count ? lines[link.line - 1] : ""
                result.append(Backlink(sourceNoteID: source.ref.id, link: link, line: link.line,
                                       snippet: Self.snippet(raw)))
            }
        }
        return result
    }

    static func normalise(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func snippet(_ line: String) -> String {
        let t = line.trimmingCharacters()
        guard t.count > maxSnippetLength else { return t }
        return String(t.prefix(maxSnippetLength)) + "…"
    }

    static func splitLines(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
            .map(String.init)
    }
}

extension Substring {
    fileprivate func trimmingCharacters() -> String {
        var s = self
        while let f = s.first, f.isWhitespace { s.removeFirst() }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return String(s)
    }
}

extension String {
    fileprivate func trimmingCharacters() -> String { Substring(self).trimmingCharacters() }
}
