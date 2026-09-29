import Foundation

/// The write side of `CourseCatalogWriter` over the in-memory world. Follows the same rules as
/// `VaultBackend`'s course writes (shared checks in `CourseWriting`).
extension FixtureStore {
    // MARK: Versions and paths

    /// What the vault would store for the course: the file text the sample generator writes, plus the
    /// course's overrides.
    private func fileText(_ course: Course, overrides: [SessionOverride]) -> String {
        SampleVaultGenerator.courseFile(course)
            + overrides.filter { $0.courseID == course.id }.map { "\n\($0.id)|\($0.cancelled)|\($0.newStart?.iso ?? "")|\($0.newRoom ?? "")|\($0.note ?? "")" }.joined()
    }

    private func hash(_ course: Course, overrides: [SessionOverride]? = nil) -> String {
        ContentHash(of: fileText(course, overrides: overrides ?? self.overrides)).hex
    }

    private func coursePath(_ course: Course) -> String {
        [semester.name, VaultPath.filename(fromTitle: course.name), "_course.md"].joined(separator: "/")
    }

    func courseVersion(id: CourseID) throws -> String { hash(try course(id: id)) }

    private func announce(_ ids: [CourseID]) { catalogUpdates.send(CatalogUpdate(courses: ids)) }

    // MARK: Create

    func createCourse(_ new: NewCourse, actor: Actor, dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let name = try CourseWriting.requireName(new.name)
        guard new.semester == semester.id else { throw MarginError.notFound("No semester \(new.semester)") }
        try requireWritable()
        let folder = VaultPath.filename(fromTitle: name)
        if courses.contains(where: { VaultPath.filename(fromTitle: $0.name) == folder }) {
            throw MarginError.conflict("\(semester.name)/\(folder) already exists")
        }
        let id = CourseWriting.courseID(for: name, taken: Set(courses.map(\.id)))
        let course = try CourseWriting.makeCourse(new, id: id, name: name, usedColors: courses.map(\.style.color))
        let entry = ChangeSet.Entry(path: coursePath(course), kind: .created, afterHash: hash(course))
        if !dryRun {
            courses.append(course)
            announce([id])
        }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }

    // MARK: Edit

    /// Applies `change` to the course; an unchanged course is an empty `ChangeSet`.
    func editCourse(id: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool, idempotencyKey: String?,
                            moved: Bool = false, change: (inout Course) throws -> Void) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let old = try course(id: id)
        try requireWritable()
        try requireBaseVersion(baseVersion, matches: hash(old), what: "Course \(id)")
        var new = old
        try change(&new)
        var entries: [ChangeSet.Entry] = []
        if new != old {
            let kind: ChangeSet.Entry.Kind = moved ? .moved : .modified
            entries = [.init(path: coursePath(new), kind: kind, fromPath: moved ? coursePath(old) : nil,
                             beforeHash: hash(old), afterHash: hash(new))]
            if !dryRun {
                courses[courses.firstIndex { $0.id == id } ?? 0] = new
                announce([id])
            }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func renameCourse(id: CourseID, to name: String, renameFolder: Bool, actor: Actor, baseVersion: String?,
                      dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        let name = try CourseWriting.requireName(name)
        let old = try course(id: id)
        let newFolder = VaultPath.filename(fromTitle: name)
        let folderChanges = renameFolder && newFolder != VaultPath.filename(fromTitle: old.name)
        if folderChanges, courses.contains(where: { $0.id != id && VaultPath.filename(fromTitle: $0.name) == newFolder }) {
            throw MarginError.conflict("\(semester.name)/\(newFolder) already exists")
        }
        return try editCourse(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                              idempotencyKey: idempotencyKey, moved: folderChanges) { $0.name = name }
    }

    func setCourseStyle(id: CourseID, icon: String?, color: String?, actor: Actor, baseVersion: String?,
                        dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        guard icon != nil || color != nil else { throw MarginError.invalid("Nothing to set: give an icon or a colour") }
        try CourseWriting.requireStyle(icon: icon, color: color)
        return try editCourse(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                              idempotencyKey: idempotencyKey) {
            $0.style = CoursePalette.style(icon: icon ?? $0.style.icon, color: color ?? $0.style.color)
        }
    }

    // MARK: Archive

    func setArchived(semester id: SemesterID, _ archived: Bool, actor: Actor, dryRun: Bool,
                     idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard id == semester.id else { throw MarginError.notFound("No semester \(id)") }
        var entries: [ChangeSet.Entry] = []
        if semester.isArchived != archived {
            let live = semester.name, archive = "_archive/\(semester.name)"
            entries = [.init(path: archived ? archive : live, kind: .moved, fromPath: archived ? live : archive),
                       .init(path: ".margin/semesters.json", kind: .modified)]
            if !dryRun {
                setSemesterArchived(archived)
                announce(courses.map(\.id))
            }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    // MARK: Overrides

    func setOverride(_ override: SessionOverride, actor: Actor, baseVersion: String?, dryRun: Bool,
                     idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let course = try self.course(id: override.courseID)
        try requireWritable()
        try requireBaseVersion(baseVersion, matches: hash(course), what: "Course \(course.id)")
        try CourseWriting.validate(override, course: course, semester: semester)
        return writeOverrides(CourseWriting.upserting(override, into: overrides), course: course, actor: actor,
                              dryRun: dryRun, key: idempotencyKey)
    }

    func removeOverride(sessionID: String, course id: CourseID, originalDate: LocalDate, actor: Actor,
                        baseVersion: String?, dryRun: Bool, idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        let course = try self.course(id: id)
        try requireWritable()
        try requireBaseVersion(baseVersion, matches: hash(course), what: "Course \(id)")
        let key = "\(sessionID)@\(originalDate.iso)"
        return writeOverrides(overrides.filter { $0.id != key || $0.courseID != id }, course: course, actor: actor,
                              dryRun: dryRun, key: idempotencyKey)
    }

    private func writeOverrides(_ new: [SessionOverride], course: Course, actor: Actor, dryRun: Bool, key: String?) -> ChangeSet {
        var entries: [ChangeSet.Entry] = []
        if new != overrides {
            entries = [.init(path: coursePath(course), kind: .modified, beforeHash: hash(course),
                             afterHash: hash(course, overrides: new))]
            if !dryRun {
                overrides = new
                announce([course.id])
            }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: key)
    }
}
