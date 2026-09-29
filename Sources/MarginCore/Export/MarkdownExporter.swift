import Foundation

/// The Markdown export of one note (`ExportService`, rules there). Pure: it gets the file text, the
/// note's path and every note of the vault, and returns the text to save.
public struct MarkdownExporter: Sendable {
    private let extractor = WikilinkExtractor()

    public init() {}

    /// - Parameters:
    ///   - content: the whole note file (frontmatter and body).
    ///   - path: the note's vault path including `.md`; relative links start from its folder.
    ///   - notes: all notes of the vault, for resolving links (`NoteRef.path` has no `.md`).
    public func export(content: String, path: String, courseID: CourseID?, notes: [NoteRef], options: ExportOptions) -> String {
        var bytes = Array(content.utf8)
        // Back to front, so the byte ranges of the links still to do stay valid.
        for link in extractor.extract(from: content).sorted(by: { $0.range.start > $1.range.start }) {
            let replacement = self.replacement(for: link, path: path, courseID: courseID, notes: notes, style: options.wikilinks)
            bytes.replaceSubrange(link.range.start..<link.range.end, with: Array(replacement.utf8))
        }
        let text = String(decoding: bytes, as: UTF8.self)
        return options.includeFrontmatter ? text : Frontmatter.parse(text).body
    }

    private func replacement(for link: Wikilink, path: String, courseID: CourseID?, notes: [NoteRef],
                             style: WikilinkExportStyle) -> String {
        if link.isEmbed, NoteIndex.isImage(link.target) {
            return "![\(Self.escape(link.name))](_files/\(Self.percentEncode(link.name)))"
        }
        let resolution = extractor.resolve(link, from: courseID, in: notes)
        switch style {
        case .plainText:
            if let alias = link.alias { return alias }
            if link.isSelfLink { return link.heading ?? link.blockID ?? "this note" }
            return link.name + (link.heading.map { " > \($0)" } ?? "")
        case .relativeLinks:
            let text = Self.escape(link.alias ?? (link.isSelfLink ? (link.heading ?? "this note") : link.name))
            let anchor = link.heading.map { "#" + Self.slug($0) } ?? ""
            switch resolution {
            case .selfLink:
                return anchor.isEmpty ? text : "[\(text)](\(anchor))"
            case .resolved(let id):
                guard let target = notes.first(where: { $0.id == id }) else { return link.alias ?? link.name }
                return "[\(text)](\(Self.relativePath(from: path, to: target.path + ".md"))\(anchor))"
            case .ambiguous, .notCreated:
                return link.alias ?? link.name + (link.heading.map { " > \($0)" } ?? "")
            }
        }
    }

    /// `../Cell Biology/Glossary.md` from `Fall 2026/Modern Europe/Linker.md`, percent-encoded.
    static func relativePath(from note: String, to target: String) -> String {
        let from = note.split(separator: "/").dropLast().map(String.init)
        let to = target.split(separator: "/").map(String.init)
        var common = 0
        while common < from.count, common < to.count - 1, from[common] == to[common] { common += 1 }
        let parts = Array(repeating: "..", count: from.count - common) + to[common...].map { percentEncode($0) }
        return parts.joined(separator: "/")
    }

    static func percentEncode(_ s: String) -> String {
        var out = ""
        for byte in s.utf8 {
            let c = Character(Unicode.Scalar(byte))
            if byte < 0x80, c.isLetter || c.isNumber || "-._~".contains(c) { out.append(c) }
            else { out += String(format: "%%%02X", Int(byte)) }
        }
        return out
    }

    /// The anchor of a heading: lower case, spaces to `-`, everything but letters, digits, `-` and `_` dropped.
    static func slug(_ heading: String) -> String {
        heading.lowercased().unicodeScalars.compactMap { u -> Character? in
            if u == " " { return "-" }
            let c = Character(u)
            return c.isLetter || c.isNumber || c == "-" || c == "_" ? c : nil
        }.map(String.init).joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}
