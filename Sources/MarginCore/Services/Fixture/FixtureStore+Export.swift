import Foundation

extension FixtureStore {
    func export(note id: NoteID, format: ExportFormat, options: ExportOptions, engine: ExportEngine) throws -> ExportedFile {
        guard let n = notes[id] else { throw MarginError.notFound("No note \(id)") }
        let refs = notes.values.map { other in
            NoteRef(id: other.summary.id, courseID: other.summary.courseID,
                    name: VaultPath.filename(fromTitle: other.fileTitle),
                    path: NoteIndex.stripExtension(path(of: other)))
        }
        return try engine.export(title: n.summary.title, path: path(of: n), content: n.content, courseID: n.summary.courseID,
                                 notes: refs, format: format, options: options)
    }
}
