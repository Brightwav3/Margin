import Foundation

/// The write side of the course catalog (`CourseCatalogWriter`): `_course.md` edits, folder moves
/// and the follow-up that keeps the index, the course model and the update streams current.
extension VaultBackend {
    // MARK: Follow-up

    /// After the app itself changed course files: reloads the model and tells listeners what changed.
    /// (The watcher does not report the app's own writes.)
    func courseFilesChanged() async {
        let old = model.courses
        await reloadModel()
        let changed = Self.changedCourses(old: old, new: model.courses)
        if !changed.isEmpty { catalogUpdates.send(CatalogUpdate(courses: changed)) }
        await tasksMayHaveChanged(paths: nil)
        await tasksStore.publish(courses: Self.coursesWithChangedExams(old: old, new: model.courses))
    }

    // MARK: Read

    /// Hash of the course's `_course.md`, the `baseVersion` of course writes.
    func courseVersion(id: CourseID) async throws -> String {
        guard let entry = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        return try await store.read(entry.filePath).version.hex
    }

    // MARK: Create

    func createCourse(_ new: NewCourse, actor: Actor, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let plan = try CourseFactory.plan(new, semesters: model.semesters, entries: model.entries)
        if await store.exists(plan.folder) { throw MarginError.conflict("\(plan.folder) already exists") }
        let entry = ChangeSet.Entry(path: plan.path.rawValue, kind: .created, afterHash: ContentHash(of: plan.text).hex)
        if !dryRun {
            try await store.create(plan.path, content: plan.text)
            await index.update(path: plan.path.rawValue, content: plan.text)
            await courseFilesChanged()
        }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }
}
