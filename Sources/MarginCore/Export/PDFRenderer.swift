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
/// PDF through PDFKit.
///
/// UNVERIFIED and not implemented: written on Linux; for now it reports that PDF export is not
/// there yet instead of producing a file.
// TODO(M10-22): PDF via PDFKit on macOS
struct MacPDFRenderer: PDFRenderer {
    func render(markdown: String, title: String) throws -> Data {
        throw MarginError.invalid("PDF export is not implemented yet")
    }
}
#endif
