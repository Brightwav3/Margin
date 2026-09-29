import Foundation

/// `_grades.md` reads and writes (`GradeService`): the file sits next to the course's `_course.md`.
extension VaultBackend {
    private func gradesPath(_ entry: VaultCourseModel.Entry) throws -> VaultPath {
        try VaultPath(components: Array(entry.filePath.components.dropLast()) + [GradeStore.fileName])
    }

    private func gradesText(_ entry: VaultCourseModel.Entry) async throws -> (text: String?, version: ContentHash) {
        let path = try gradesPath(entry)
        guard await store.exists(path) else { return (nil, ContentHash(of: "")) }
        let (text, version) = try await store.read(path)
        return (text, version)
    }

    func grades(course id: CourseID) async throws -> [Grade] {
        guard let entry = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        return try await gradesText(entry).text.map { GradeStore.parse($0, course: id) } ?? []
    }

    func gradeAverage(course id: CourseID) async throws -> GradeSummary? {
        let items = try await grades(course: id)
        guard let entry = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        return GradeCalculator.course(id: id, grading: entry.course.grading, grades: items).summary
    }

    func gradesVersion(course id: CourseID) async throws -> String {
        guard let entry = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        return try await gradesText(entry).version.hex
    }

    func addGrade(_ grade: Grade, actor: Actor, baseVersion: String?, dryRun: Bool,
                  idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let entry = try writableEntry(grade.courseID)
        let path = try gradesPath(entry)
        let (old, version) = try await gradesText(entry)
        try requireBaseVersion(baseVersion, matches: version.hex, what: "Grades of \(entry.course.id)")
        let new = try GradeStore.appending(grade, to: old, course: entry.course.id, courseName: entry.course.name)
        let change = ChangeSet.Entry(path: path.rawValue, kind: old == nil ? .created : .modified,
                                     beforeHash: old == nil ? nil : version.hex, afterHash: ContentHash(of: new).hex)
        if !dryRun {
            if old == nil { try await store.create(path, content: new) }
            else { try await store.write(path, content: new, expectedVersion: version) }
        }
        return finish(actor: actor, entries: [change], dryRun: dryRun, key: idempotencyKey)
    }
}
