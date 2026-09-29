import Foundation

/// Changing or cancelling a single class (M10-14.B): the override is stored in the course's
/// `_course.md` (`SessionOverrideCodec`) and shows in `sessions(week:)` right away.
extension VaultBackend {
    /// Overrides of all courses of `semester`, for `ServiceRules.occurrences`.
    func overrides(in semester: Semester) -> [SessionOverride] {
        model.entries.filter { $0.course.semester == semester.id }.flatMap(\.overrides)
    }

    func setOverride(_ override: SessionOverride, actor: Actor, baseVersion: String?, dryRun: Bool,
                     idempotencyKey: String?) async throws -> ChangeSet {
        let semester = model.entry(override.courseID).flatMap { entry in model.semesters.first { $0.id == entry.course.semester } }
        return try await editCourseFile(id: override.courseID, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                        idempotencyKey: idempotencyKey) { fm, course in
            guard let semester else { throw MarginError.notFound("No semester \(course.semester)") }
            try CourseWriting.validate(override, course: course, semester: semester)
            let (existing, unreadable) = SessionOverrideCodec.read(fm, courseID: course.id)
            // What is stored is what the file can say: a cancelled class keeps no new time or room.
            let stored = SessionOverrideCodec.decode(SessionOverrideCodec.encode(override), courseID: course.id) ?? override
            guard existing.first(where: { $0.id == override.id }) != stored else { return false }
            SessionOverrideCodec.write(CourseWriting.upserting(stored, into: existing), unreadable: unreadable, to: &fm)
            return true
        }
    }

    func clearOverride(sessionID: String, course id: CourseID, originalDate: LocalDate, actor: Actor,
                       baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet {
        try await editCourseFile(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                 idempotencyKey: idempotencyKey) { fm, course in
            let (existing, unreadable) = SessionOverrideCodec.read(fm, courseID: course.id)
            let key = "\(sessionID)@\(originalDate.iso)"
            let remaining = existing.filter { $0.id != key }
            guard remaining.count != existing.count else { return false }
            SessionOverrideCodec.write(remaining, unreadable: unreadable, to: &fm)
            return true
        }
    }
}
