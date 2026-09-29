import Foundation

/// `GradeService` over the in-memory world; same rules as `VaultBackend+Grades`.
extension FixtureStore {
    private func gradeItems(_ id: CourseID) throws -> (course: Course, items: [Grade]) {
        let course = try self.course(id: id)
        return (course, grades.filter { $0.courseID == id })
    }

    private func gradesHash(_ course: Course, _ items: [Grade]) -> String {
        ContentHash(of: items.isEmpty ? "" : GradeStore.canonicalText(items, course: course.id, courseName: course.name)).hex
    }

    func grades(course id: CourseID) throws -> [Grade] { try gradeItems(id).items }

    func gradeAverage(course id: CourseID) throws -> GradeSummary? {
        let (course, items) = try gradeItems(id)
        return GradeCalculator.course(id: id, grading: course.grading, grades: items).summary
    }

    func gradesVersion(course id: CourseID) throws -> String {
        let (course, items) = try gradeItems(id)
        return gradesHash(course, items)
    }

    func addGrade(_ grade: Grade, actor: Actor, baseVersion: String?, dryRun: Bool,
                  idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let (course, items) = try gradeItems(grade.courseID)
        try requireWritable()
        let before = gradesHash(course, items)
        try requireBaseVersion(baseVersion, matches: before, what: "Grades of \(course.id)")
        let old = items.isEmpty ? nil : GradeStore.canonicalText(items, course: course.id, courseName: course.name)
        // Same checks and the same id rule as the vault: append to the text, read it back.
        let text = try GradeStore.appending(grade, to: old, course: course.id, courseName: course.name)
        let added = GradeStore.parse(text, course: course.id).last
        let path = [semester.name, VaultPath.filename(fromTitle: course.name), GradeStore.fileName].joined(separator: "/")
        let change = ChangeSet.Entry(path: path, kind: items.isEmpty ? .created : .modified,
                                     beforeHash: items.isEmpty ? nil : before, afterHash: ContentHash(of: text).hex)
        if !dryRun, let added { grades.append(added) }
        return finish(actor: actor, entries: [change], dryRun: dryRun, key: idempotencyKey)
    }
}
