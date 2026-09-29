/// Exporting one note to a file (M10-22). Read only: nothing in the vault changes.
///
/// Rules both implementations obey, checked by `Tests/Conformance/ExportServiceConformanceTests.swift`:
///
/// - **Markdown:** the note file as it is, with these changes: the frontmatter block is left out
///   unless `ExportOptions.includeFrontmatter`; `[[wikilinks]]` become plain text or relative Markdown
///   links (`WikilinkExportStyle`); `![[image.png]]` becomes `![image.png](_files/image.png)` (the
///   attachment folder next to the note); other embeds (`![[Note]]`) are turned into links like
///   ordinary wikilinks, not copied in. Code blocks, inline code, Markdown links, task checkboxes,
///   `^block-ids` and line endings are untouched. The file name is the note title plus `.md`.
/// - **PDF:** needs a renderer (PDFKit on macOS). Where there is none the result is
///   `.invalid("PDF export requires macOS")`.
/// - An unknown note is `.notFound`.
public protocol ExportService: Sendable {
    func export(note: NoteID, format: ExportFormat, options: ExportOptions) async throws -> ExportedFile
}

extension ExportService {
    /// Export with the default options (no frontmatter, links as plain text).
    public func export(note: NoteID, format: ExportFormat) async throws -> ExportedFile {
        try await export(note: note, format: format, options: ExportOptions())
    }
}
