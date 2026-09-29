import Foundation

/// Archived semesters (M10-13.B, M11-04.B): archiving, restoring, and the rule that nothing inside
/// an archived semester is written.
extension VaultBackend {
    /// `_archive/<semester>/<course>/<note>.md`: a note of an archived semester. These are readable
    /// (`notes(course:)`, `open(id:)`) but never listed with the live notes, counted as tasks, or written.
    static func isArchivedNotePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard parts.count >= 4, parts[0] == SemesterArchiver.folderName, path.lowercased().hasSuffix(".md"),
              let last = parts.last, !last.hasPrefix("_"), !parts[1].hasPrefix("."), !parts[2].hasPrefix("_")
        else { return false }
        return true
    }

    /// The archived course a note path belongs to.
    func archivedEntry(forNotePath path: String) -> VaultCourseModel.Entry? {
        model.entries.first { $0.archived && path.hasPrefix("\(SemesterArchiver.folderName)/\($0.semesterFolder)/\($0.folder)/") }
    }

    /// Throws `.readOnly` for a path inside `_archive/`.
    func requireWritable(path: String) throws {
        if path.hasPrefix(SemesterArchiver.folderName + "/") {
            throw MarginError.readOnly("\(path) is in an archived semester and read-only")
        }
    }

    /// Throws `.readOnly` when the course's semester is archived.
    func requireWritable(course entry: VaultCourseModel.Entry) throws { _ = try writableEntry(entry.course.id) }

    // MARK: Archive and restore

    func setArchived(semester id: SemesterID, _ archived: Bool, actor: Actor, dryRun: Bool,
                     idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let semester = model.semesters.first(where: { $0.id == id }) else {
            throw MarginError.notFound("No semester \(id)")
        }
        guard semester.isArchived != archived else {
            return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey)
        }
        let affected = model.entries.filter { $0.semesterFolder == semester.name }.map(\.course.id).sorted()
        let outcome = try await SemesterArchiver(store: store).setArchived(archived, semester: semester, dryRun: dryRun)
        if !dryRun {
            if let moved = outcome.moved { await followFolderMove(from: moved.from, to: moved.to) }
            await courseFilesChanged()
            // Courses did not change, but where they live and whether they can be written did.
            if !affected.isEmpty { catalogUpdates.send(CatalogUpdate(courses: affected)) }
        }
        return finish(actor: actor, entries: outcome.entries, dryRun: dryRun, key: idempotencyKey)
    }
}
