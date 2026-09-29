import Foundation

extension VaultBackend {
    func export(note id: NoteID, format: ExportFormat, options: ExportOptions, engine: ExportEngine) async throws -> ExportedFile {
        guard let r = await index.note(byID: id), Self.isNotePath(r.path) || Self.isArchivedNotePath(r.path) else {
            throw MarginError.notFound("No note \(id)")
        }
        let (content, _) = try await store.read(VaultPath(r.path))
        let refs = await index.allNotes.filter { Self.isNotePath($0.path) || Self.isArchivedNotePath($0.path) }.map(\.ref)
        return try engine.export(title: r.title, path: r.path, content: content, courseID: r.courseID, notes: refs,
                                 format: format, options: options)
    }
}

/// `ExportService` over a vault.
public struct VaultExportService: ExportService {
    let backend: VaultBackend
    private let engine: ExportEngine

    init(backend: VaultBackend, pdf: (any PDFRenderer)? = DefaultPDFRenderer.renderer) {
        self.backend = backend; engine = ExportEngine(pdf: pdf)
    }

    public func export(note: NoteID, format: ExportFormat, options: ExportOptions) async throws -> ExportedFile {
        try await backend.export(note: note, format: format, options: options, engine: engine)
    }
}
