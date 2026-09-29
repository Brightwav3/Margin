import Foundation

/// Semester writes (M11-05.B): the array of `.margin/semesters.json`, plus the semester folder when a
/// semester is renamed. Same file, same format as `SemesterArchiver` and `VaultCourseModel`.
extension VaultBackend {
    private static var semestersPath: VaultPath { get throws { try VaultPath(SemesterArchiver.semestersFile) } }

    /// The semesters stored in the file (not the ones only derived from folders) and its version.
    private func readSemesterFile() async throws -> (list: [Semester], text: String?, version: ContentHash) {
        let path = try Self.semestersPath
        guard await store.exists(path) else { return ([], nil, ContentHash(of: "")) }
        let (text, version) = try await store.read(path)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ([], text, version) }
        do { return (try JSONDecoder().decode([Semester].self, from: Data(text.utf8)), text, version) }
        catch { throw MarginError.invalid("\(SemesterArchiver.semestersFile) is not valid, not touching it: \(error)") }
    }

    func semesterVersion() async throws -> String { try await readSemesterFile().version.hex }

    /// `list` with `semester` in place of the entry it replaces (same id or name), or appended.
    private static func replacing(_ old: Semester?, with semester: Semester, in list: [Semester]) -> [Semester] {
        var list = list
        if let old, let i = list.firstIndex(where: { $0.id == old.id || $0.name == old.name }) { list[i] = semester }
        else { list.append(semester) }
        return list
    }

    private func entry(for text: String, file: (text: String?, version: ContentHash)) throws -> ChangeSet.Entry {
        .init(path: SemesterArchiver.semestersFile, kind: file.text == nil ? .created : .modified,
              beforeHash: file.text == nil ? nil : file.version.hex, afterHash: ContentHash(of: text).hex)
    }

    private func writeSemesterFile(_ text: String, old: (text: String?, version: ContentHash)) async throws {
        let path = try Self.semestersPath
        if old.text != nil { try await store.write(path, content: text, expectedVersion: old.version) }
        else { try await store.create(path, content: text) }
    }

    func createSemester(_ new: NewSemester, actor: Actor, baseVersion: String?, dryRun: Bool,
                        idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let file = try await readSemesterFile()
        try requireBaseVersion(baseVersion, matches: file.version.hex, what: "Semesters")
        let semester = try SemesterRules.make(new, among: model.semesters)
        let text = SemesterRules.json(SemesterRules.sorted(file.list + [semester]))
        let entries = [try entry(for: text, file: (file.text, file.version))]
        if !dryRun {
            // The folder first: an empty folder is harmless, a listed semester without one is not.
            try await SemesterFactory(store: store).createFolder(for: semester)
            try await writeSemesterFile(text, old: (file.text, file.version))
            await courseFilesChanged()
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func updateSemester(id: SemesterID, _ update: SemesterUpdate, actor: Actor, baseVersion: String?, dryRun: Bool,
                        idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let old = model.semesters.first(where: { $0.id == id }) else { throw MarginError.notFound("No semester \(id)") }
        let file = try await readSemesterFile()
        try requireBaseVersion(baseVersion, matches: file.version.hex, what: "Semesters")
        let new = try SemesterRules.apply(update, to: old, among: model.semesters.filter { $0.id != id })
        guard new != old else { return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey) }

        let text = SemesterRules.json(SemesterRules.sorted(Self.replacing(old, with: new, in: file.list)))
        var entries: [ChangeSet.Entry] = []
        var folders: (from: VaultPath, to: VaultPath)?
        if new.name != old.name {
            let from = try VaultPath(components: [old.name]), to = try VaultPath(components: [new.name])
            if await store.exists(from) {
                let caseOnly = old.name.lowercased() == new.name.lowercased()
                if !caseOnly, await store.exists(to) { throw MarginError.conflict("\(to) already exists") }
                folders = (from, to)
                entries.append(.init(path: to.rawValue, kind: .moved, fromPath: from.rawValue))
            }
        }
        entries.append(try entry(for: text, file: (file.text, file.version)))
        if !dryRun {
            let affected = model.entries.filter { $0.semesterFolder == old.name }.map(\.course.id).sorted()
            try await writeSemesterFile(text, old: (file.text, file.version))
            if let folders {
                do { try await store.rename(folders.from, to: folders.to) } catch {
                    // Put the old list back, so the file and the folders agree again.
                    if let oldText = file.text { _ = try? await store.write(try Self.semestersPath, content: oldText) }
                    else { _ = try? await store.trash(try Self.semestersPath) }
                    throw error
                }
                await followFolderMove(from: folders.from, to: folders.to)
            }
            await courseFilesChanged()
            if !affected.isEmpty { catalogUpdates.send(CatalogUpdate(courses: affected)) }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func deleteSemester(id: SemesterID, actor: Actor, baseVersion: String?, dryRun: Bool,
                        idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let old = model.semesters.first(where: { $0.id == id }) else { throw MarginError.notFound("No semester \(id)") }
        if old.isArchived { throw MarginError.readOnly("\(old.name) is archived and read-only") }
        let file = try await readSemesterFile()
        try requireBaseVersion(baseVersion, matches: file.version.hex, what: "Semesters")
        if model.entries.contains(where: { $0.semesterFolder == old.name }) {
            throw MarginError.conflict("\(old.name) still has courses; archive it instead")
        }
        var list = file.list
        list.removeAll { $0.id == old.id || $0.name == old.name }
        guard list.count != file.list.count else { return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey) }
        let text = SemesterRules.json(list)
        let entries = [try entry(for: text, file: (file.text, file.version))]
        if !dryRun {
            try await writeSemesterFile(text, old: (file.text, file.version))
            await courseFilesChanged()
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }
}
