import Foundation

/// Embedded files of notes (`NoteRepository.attachment`): pictures and PDFs next to the notes.
enum AttachmentRules {
    static let maxBytes: Int64 = 25 * 1024 * 1024

    /// A name that stays inside the vault's user files.
    static func check(_ name: String) throws {
        let parts = name.split(separator: "/").map(String.init)
        guard !name.isEmpty, !name.hasPrefix("/"), !parts.contains(".."), !parts.contains(where: { $0.hasPrefix(".") }) else {
            throw MarginError.invalid("'\(name)' is not a file in the vault")
        }
    }
}

extension VaultBackend {
    func attachment(named name: String, near note: NoteID?) async throws -> Data {
        try AttachmentRules.check(name)
        var candidates: [VaultPath] = []
        if let note, let path = await index.note(byID: note)?.path, let folder = (try? VaultPath(path))?.parent {
            if let p = try? folder.appending(path: name) { candidates.append(p) }
            if let p = try? folder.appending("_files").appending(path: name) { candidates.append(p) }
        }
        if let p = try? VaultPath(name) { candidates.append(p) }
        var found: VaultPath?
        for c in candidates where (try? await store.size(of: c)) ?? nil != nil { found = c; break }
        if found == nil, !name.contains("/") { found = try await store.findFile(named: name) }
        guard let path = found else { throw MarginError.notFound("No file \(name)") }
        if let size = try await store.size(of: path), size > AttachmentRules.maxBytes {
            throw MarginError.invalid("\(name) is larger than 25 MB")
        }
        return try await store.readData(path).data
    }
}
