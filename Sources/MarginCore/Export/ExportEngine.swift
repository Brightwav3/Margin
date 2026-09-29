import Foundation

/// The behaviour of `ExportService`, shared by the fixture and the vault implementation.
struct ExportEngine: Sendable {
    var pdf: (any PDFRenderer)?

    init(pdf: (any PDFRenderer)? = DefaultPDFRenderer.renderer) { self.pdf = pdf }

    func export(title: String, path: String, content: String, courseID: CourseID?, notes: [NoteRef], format: ExportFormat,
                options: ExportOptions) throws -> ExportedFile {
        let name = VaultPath.filename(fromTitle: title)
        let markdown = MarkdownExporter().export(content: content, path: path, courseID: courseID, notes: notes, options: options)
        switch format {
        case .markdown:
            return ExportedFile(fileName: name + ".md", format: .markdown, data: Data(markdown.utf8))
        case .pdf:
            guard let pdf else { throw MarginError.invalid(DefaultPDFRenderer.unavailableMessage) }
            return ExportedFile(fileName: name + ".pdf", format: .pdf, data: try pdf.render(markdown: markdown, title: title))
        }
    }
}
