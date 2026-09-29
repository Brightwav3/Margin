import Foundation

/// What a note is exported as.
public enum ExportFormat: String, Codable, Sendable, Hashable, CaseIterable {
    case markdown, pdf
}

/// What `[[wikilinks]]` become in an exported Markdown file.
public enum WikilinkExportStyle: String, Codable, Sendable, Hashable, CaseIterable {
    /// The link text only: `[[Glossary]]` is `Glossary`, `[[Glossary|the terms]]` is `the terms`,
    /// `[[Glossary#Enzyme]]` is `Glossary > Enzyme`.
    case plainText
    /// A relative Markdown link to the note's file in the vault: `[Glossary](../Cell%20Biology/Glossary.md)`,
    /// with `#heading` when the wikilink had one. Links that do not resolve to exactly one note
    /// (not created yet, ambiguous) fall back to plain text.
    case relativeLinks
}

/// Options of an export. Only Markdown uses them.
public struct ExportOptions: Codable, Sendable, Hashable {
    /// Keep the YAML frontmatter block at the top (verbatim). Default: leave it out.
    public var includeFrontmatter: Bool
    public var wikilinks: WikilinkExportStyle

    public init(includeFrontmatter: Bool = false, wikilinks: WikilinkExportStyle = .plainText) {
        self.includeFrontmatter = includeFrontmatter; self.wikilinks = wikilinks
    }
}

/// The result of an export: the bytes and a file name to save them under.
public struct ExportedFile: Codable, Sendable, Hashable {
    /// `Lecture 9.md`: the note title made safe as a file name, plus the extension.
    public var fileName: String
    public var format: ExportFormat
    public var data: Data

    public init(fileName: String, format: ExportFormat, data: Data) {
        self.fileName = fileName; self.format = format; self.data = data
    }

    /// The text of a Markdown export.
    public var text: String? { format == .markdown ? String(data: data, encoding: .utf8) : nil }
}
