import Foundation

/// Course settings, archiving one course and deleting a course (`CourseCatalogWriter.update`,
/// `setArchived(course:)`, `delete`).
extension VaultBackend {
    func updateCourse(id: CourseID, _ update: CourseUpdate, actor: Actor, baseVersion: String?, dryRun: Bool,
                      idempotencyKey: String?) async throws -> ChangeSet {
        try await editCourseFile(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                 idempotencyKey: idempotencyKey) { fm, course in
            let new = try CourseWriting.applying(update, to: course)
            var changed = false
            func text(_ key: String, _ old: String?, _ value: String?) {
                guard old != value else { return }
                if let value, !value.isEmpty { fm.set(key, .string(value)) } else { fm.remove(key) }
                changed = true
            }
            text("code", course.code, new.code)
            text("professor", course.professor, new.professor)
            text("room", course.room, new.room)
            text("faculty", course.faculty, new.faculty)
            if new.credits != course.credits {
                if let credits = new.credits { fm.set("credits", .number(Double(credits))) } else { fm.remove("credits") }
                changed = true
            }
            // An untouched list is not rewritten, so hand-made formatting of it survives.
            if new.sessions != course.sessions {
                Self.setList("sessions", new.sessions.map(SyllabusCodec.entry), in: &fm); changed = true
            }
            if new.exams != course.exams {
                Self.setList("exams", new.exams.map(SyllabusCodec.entry), in: &fm); changed = true
            }
            return changed
        }
    }

    func setArchived(course id: CourseID, _ archived: Bool, actor: Actor, baseVersion: String?, dryRun: Bool,
                     idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let entry = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        if model.semesters.first(where: { $0.id == entry.course.semester })?.isArchived == true {
            throw MarginError.readOnly("\(entry.semesterFolder) is archived and read-only")
        }
        guard entry.archived != archived else { return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey) }
        let version = try await store.read(entry.filePath).version
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Course \(id)")
        let live = try VaultPath(components: [entry.semesterFolder, entry.folder])
        let archive = try VaultPath(components: [SemesterArchiver.folderName, entry.semesterFolder, entry.folder])
        let (from, to) = archived ? (live, archive) : (archive, live)
        if await store.exists(to) { throw MarginError.conflict("\(to) already exists") }
        let entries = [ChangeSet.Entry(path: to.rawValue, kind: .moved, fromPath: from.rawValue)]
        if !dryRun {
            try await store.rename(from, to: to)
            await followFolderMove(from: from, to: to)
            await courseFilesChanged()
            catalogUpdates.send(CatalogUpdate(courses: [id]))
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func deleteCourse(id: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
                      idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let entry = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        if model.semesters.first(where: { $0.id == entry.course.semester })?.isArchived == true {
            throw MarginError.readOnly("\(entry.semesterFolder) is archived and read-only")
        }
        let version = try await store.read(entry.filePath).version
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Course \(id)")
        let folder = try VaultPath(components: (entry.archived ? [SemesterArchiver.folderName] : [])
                                   + [entry.semesterFolder, entry.folder])
        let entries = [ChangeSet.Entry(path: entry.filePath.rawValue, kind: .deleted, beforeHash: version.hex)]
        if !dryRun {
            try await store.trash(folder)
            let prefix = folder.rawValue + "/"
            var gone: [String] = []
            for record in await index.allNotes where record.path.hasPrefix(prefix) {
                _ = await index.remove(path: record.path)
                gone.append(record.path)
            }
            _ = await index.remove(path: entry.filePath.rawValue)
            await tasksMayHaveChanged(paths: gone)
            await courseFilesChanged()
            catalogUpdates.send(CatalogUpdate(courses: [id]))
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    /// Courses archived on their own: in `_archive/`, in a semester that is not archived.
    func archivedCourses() -> [Course] {
        let archivedSemesters = Set(model.semesters.filter(\.isArchived).map(\.id))
        return model.entries.filter { $0.archived && !archivedSemesters.contains($0.course.semester) }
            .map(\.course).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func setList(_ key: String, _ items: [FrontmatterValue], in fm: inout Frontmatter) {
        if items.isEmpty { fm.remove(key) } else { fm.set(key, .list(items)) }
    }
}
