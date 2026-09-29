import Foundation

/// The write side of `SemesterStore` over the in-memory world. Follows the same rules as
/// `VaultBackend`'s semester writes (shared checks in `SemesterRules`).
extension FixtureStore {
    func semesterVersion() -> String { SemesterRules.version(of: semesters()) }

    private static let semestersFile = ".margin/semesters.json"

    private func semestersEntry(_ new: [Semester]) -> ChangeSet.Entry {
        .init(path: Self.semestersFile, kind: .modified, beforeHash: semesterVersion(),
              afterHash: SemesterRules.version(of: SemesterRules.sorted(new)))
    }

    func createSemester(_ new: NewSemester, actor: Actor, baseVersion: String?, dryRun: Bool,
                        idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        try requireBaseVersion(baseVersion, matches: semesterVersion(), what: "Semesters")
        let semester = try SemesterRules.make(new, among: semesters())
        let entry = semestersEntry(semesters() + [semester])
        if !dryRun { extraSemesters.append(semester) }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }

    func updateSemester(id: SemesterID, _ update: SemesterUpdate, actor: Actor, baseVersion: String?, dryRun: Bool,
                        idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let old = semesters().first(where: { $0.id == id }) else { throw MarginError.notFound("No semester \(id)") }
        try requireBaseVersion(baseVersion, matches: semesterVersion(), what: "Semesters")
        let new = try SemesterRules.apply(update, to: old, among: semesters().filter { $0.id != id })
        guard new != old else { return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey) }
        var entries: [ChangeSet.Entry] = []
        if new.name != old.name { entries.append(.init(path: new.name, kind: .moved, fromPath: old.name)) }
        entries.append(semestersEntry(semesters().filter { $0.id != id } + [new]))
        if !dryRun {
            if old.id == semester.id {
                semester = new
                for i in courses.indices { courses[i].semester = new.id }
            } else if let i = extraSemesters.firstIndex(where: { $0.id == id }) {
                extraSemesters[i] = new
            }
            if old.id != new.id { catalogUpdates.send(CatalogUpdate(courses: courses.filter { $0.semester == new.id }.map(\.id).sorted())) }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }

    func deleteSemester(id: SemesterID, actor: Actor, baseVersion: String?, dryRun: Bool,
                        idempotencyKey: String?) throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        guard let old = semesters().first(where: { $0.id == id }) else { throw MarginError.notFound("No semester \(id)") }
        if old.isArchived { throw MarginError.readOnly("\(old.name) is archived and read-only") }
        try requireBaseVersion(baseVersion, matches: semesterVersion(), what: "Semesters")
        // The semester with the fixture's courses is the world itself and cannot go.
        if old.id == semester.id { throw MarginError.conflict("\(old.name) still has courses; archive it instead") }
        let entry = semestersEntry(semesters().filter { $0.id != id })
        if !dryRun { extraSemesters.removeAll { $0.id == id } }
        return finish(actor: actor, entries: [entry], dryRun: dryRun, key: idempotencyKey)
    }
}
