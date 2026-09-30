import Foundation

/// The write side of the course catalog (`CourseCatalogWriter`): `_course.md` edits, folder moves
/// and the follow-up that keeps the index, the course model and the update streams current.
extension VaultBackend {
    // MARK: Follow-up

    /// After the app itself changed course files: reloads the model and tells listeners what changed.
    /// (The watcher does not report the app's own writes.)
    func courseFilesChanged() async {
        let old = model.entries
        await reloadModel()
        let changed = Self.changedCourses(old: old, new: model.entries)
        if !changed.isEmpty { catalogUpdates.send(CatalogUpdate(courses: changed)) }
        await tasksMayHaveChanged(paths: nil)
        await tasksStore.publish(courses: Self.coursesWithChangedExams(old: old.map(\.course), new: model.courses))
    }

    // MARK: Read

    /// Hash of the course's `_course.md`, the `baseVersion` of course writes.
    func courseVersion(id: CourseID) async throws -> String {
        guard let entry = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        return try await store.read(entry.filePath).version.hex
    }

    // MARK: Editing `_course.md`

    /// The entry of a course that may be written: known, and not in an archived semester.
    func writableEntry(_ id: CourseID) throws -> VaultCourseModel.Entry {
        guard let entry = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        let semester = model.semesters.first { $0.id == entry.course.semester }
        if entry.archived || semester?.isArchived == true {
            throw MarginError.readOnly("\(entry.semesterFolder) is archived and read-only")
        }
        return entry
    }

    /// Rewrites the frontmatter of a course's `_course.md` through `change` and nothing else: the
    /// other keys, their order, comments and the body stay byte for byte (`Frontmatter.set`). A file
    /// that would have a problem it did not have before is refused (`CourseValidator`).
    ///
    /// `change` returns whether it changed anything; when it did not, the `ChangeSet` is empty.
    func editCourseFile(id: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?,
                        change: (_ fm: inout Frontmatter, _ course: Course) throws -> Bool) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let entry = try writableEntry(id)
        let (content, version) = try await store.read(entry.filePath)
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Course \(id)")
        var entries: [ChangeSet.Entry] = []
        if let newContent = try Self.edit(content, course: entry.course, change: change) {
            entries = [.init(path: entry.filePath.rawValue, kind: .modified, beforeHash: version.hex,
                             afterHash: ContentHash(of: newContent).hex)]
            if !dryRun {
                try await store.write(entry.filePath, content: newContent, expectedVersion: version)
                await index.update(path: entry.filePath.rawValue, content: newContent)
                await courseFilesChanged()
            }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    /// The new file text, or `nil` when `change` changes nothing.
    static func edit(_ content: String, course: Course,
                     change: (inout Frontmatter, Course) throws -> Bool) throws -> String? {
        let (parsed, body) = Frontmatter.parse(content)
        guard var fm = parsed else { throw MarginError.invalid("\(course.name): _course.md has no frontmatter block") }
        let known = Set(CourseValidator.validate(fm).map(\.message))
        guard try change(&fm, course) else { return nil }
        if let problem = CourseValidator.validate(fm).first(where: { !known.contains($0.message) }) { throw problem }
        let new = fm.render() + body
        return new == content ? nil : new
    }

    // MARK: Rename, colour, icon

    func renameCourse(id: CourseID, to name: String, renameFolder: Bool, actor: Actor, baseVersion: String?,
                      dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        let name = try CourseWriting.requireName(name)
        let entry = try writableEntry(id)
        let newFolder = VaultPath.filename(fromTitle: name)
        guard renameFolder, newFolder != entry.folder else {
            return try await editCourseFile(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                            idempotencyKey: idempotencyKey) { fm, _ in Self.setName(name, in: &fm) }
        }

        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let oldFolder = try VaultPath(components: [entry.semesterFolder, entry.folder])
        let targetFolder = try VaultPath(components: [entry.semesterFolder, newFolder])
        let caseOnly = newFolder.lowercased() == entry.folder.lowercased()
        let taken = model.entries.contains {
            $0.course.id != id && $0.semesterFolder == entry.semesterFolder && $0.folder.lowercased() == newFolder.lowercased()
        }
        let onDisk = caseOnly ? false : await store.exists(targetFolder)
        if taken || onDisk {
            throw MarginError.conflict("\(targetFolder) already exists")
        }
        let oldFile = entry.filePath
        let (content, version) = try await store.read(oldFile)
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Course \(id)")
        // The id must survive the move: without an `id:` it would be derived from the folder name.
        let newContent = try Self.edit(content, course: entry.course) { fm, course in
            var changed = Self.setName(name, in: &fm)
            if fm.string(for: "id") == nil { fm.set("id", .string(course.id)); changed = true }
            return changed
        } ?? content
        let newFile = try targetFolder.appending("_course.md")
        let result = ChangeSet.Entry(path: newFile.rawValue, kind: .moved, fromPath: oldFile.rawValue,
                                     beforeHash: version.hex, afterHash: ContentHash(of: newContent).hex)
        if !dryRun {
            if newContent != content { try await store.write(oldFile, content: newContent, expectedVersion: version) }
            try await store.rename(oldFolder, to: targetFolder)
            await followFolderMove(from: oldFolder, to: targetFolder)
            await courseFilesChanged()
        }
        return finish(actor: actor, entries: [result], dryRun: dryRun, key: idempotencyKey)
    }

    private static func setName(_ name: String, in fm: inout Frontmatter) -> Bool {
        guard fm.string(for: "name") != name else { return false }
        fm.set("name", .string(name))
        return true
    }

    /// Brings the index up to date after `VaultStore.rename` moved a folder: notes and `_course.md`
    /// follow their new paths, notes whose links the rename observer rewrote are read again.
    func followFolderMove(from: VaultPath, to: VaultPath) async {
        let prefix = from.rawValue + "/"
        var touched: [String] = []
        for record in await index.allNotes where record.path.hasPrefix(prefix) {
            let moved = to.rawValue + "/" + record.path.dropFirst(prefix.count)
            await index.rename(from: record.path, to: moved)
            touched += [record.path, moved]
        }
        await resyncIndex(afterMovingFolderFrom: from.rawValue, to: to.rawValue)
        for rewritten in await rewriter.lastReport.notesRewritten {
            _ = try? await index.update(path: rewritten.rawValue)
            touched.append(rewritten.rawValue)
        }
        await tasksMayHaveChanged(paths: touched)
    }

    func setCourseStyle(id: CourseID, icon: String?, color: String?, actor: Actor, baseVersion: String?,
                        dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        guard icon != nil || color != nil else { throw MarginError.invalid("Nothing to set: give an icon or a colour") }
        try CourseWriting.requireStyle(icon: icon, color: color)
        return try await editCourseFile(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                        idempotencyKey: idempotencyKey) { fm, _ in
            var changed = false
            if let icon, fm.string(for: "icon") != icon { fm.set("icon", .string(icon)); changed = true }
            if let color, fm.string(for: "color") != color { fm.set("color", .string(color)); changed = true }
            return changed
        }
    }

    // MARK: Create

    func createCourse(_ new: NewCourse, actor: Actor, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let plan = try CourseFactory.plan(new, semesters: model.semesters, entries: model.entries)
        if await store.exists(plan.folder) {
            // An empty folder is what an interrupted earlier create leaves behind (the store makes the
            // folder before the file, e.g. when the disk fills up): a retry must not trip over it.
            let files = (try? await store.list(under: plan.folder)) ?? [plan.path]
            if !files.isEmpty { throw MarginError.conflict("\(plan.folder) already exists") }
        }
        let entry = ChangeSet.Entry(path: plan.path.rawValue, kind: .created, afterHash: ContentHash(of: plan.text).hex)
        if !dryRun {
            try await store.create(plan.path, content: plan.text)
            await index.update(path: plan.path.rawValue, content: plan.text)
            await courseFilesChanged()
        }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }
}
