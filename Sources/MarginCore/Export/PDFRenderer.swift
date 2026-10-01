import Foundation

/// Turns exported Markdown into PDF bytes. The platform part of `ExportService`.
public protocol PDFRenderer: Sendable {
    func render(markdown: String, title: String) throws -> Data
}

/// What an export uses for PDF when no renderer is given.
public enum DefaultPDFRenderer {
    public static let unavailableMessage = "PDF export requires macOS"

    public static var renderer: (any PDFRenderer)? {
        #if os(macOS)
        MacPDFRenderer()
        #else
        nil
        #endif
    }
}

#if os(macOS)
/// PDF through Core Text: A4 pages, the title on top, page numbers at the foot. Markdown is laid
/// out as a reader sees it (headings, lists, tasks, quotes, code, bold, italic, highlight); links
/// are already plain text (`MarkdownExporter`).
struct MacPDFRenderer: PDFRenderer {
    func render(markdown: String, title: String) throws -> Data {
        try PDFLayout().render(markdown: markdown, title: title)
    }
}
#endif
