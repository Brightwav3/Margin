import Foundation

/// `SyllabusService`: writes the timetable, exams and grading of a draft into `_course.md`.
extension VaultBackend {
    func syllabusDraft(course id: CourseID) throws -> SyllabusDraft {
        guard let entry = model.entry(id) else { throw MarginError.notFound("No course \(id)") }
        return SyllabusDraft(course: entry.course)
    }

    func applySyllabus(_ draft: SyllabusDraft, to id: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
                       idempotencyKey: String?) async throws -> ChangeSet {
        try await editCourseFile(id: id, actor: actor, baseVersion: baseVersion, dryRun: dryRun,
                                 idempotencyKey: idempotencyKey) { fm, course in
            let new = try SyllabusRules.apply(draft, to: course)
            var changed = false
            // An untouched section is not rewritten, so hand-made formatting of it survives.
            if new.sessions != course.sessions {
                Self.set("sessions", new.sessions.map(SyllabusCodec.entry), in: &fm); changed = true
            }
            if new.exams != course.exams {
                Self.set("exams", new.exams.map(SyllabusCodec.entry), in: &fm); changed = true
            }
            if new.grading != course.grading {
                Self.set("grading", new.grading.map(SyllabusCodec.entry), in: &fm); changed = true
            }
            return changed
        }
    }

    private static func set(_ key: String, _ items: [FrontmatterValue], in fm: inout Frontmatter) {
        if items.isEmpty { fm.remove(key) } else { fm.set(key, .list(items)) }
    }
}

/// The `_course.md` entries of sessions, exams and grading parts (same keys as
/// `SampleVaultGenerator.courseFile`).
enum SyllabusCodec {
    static func entry(_ s: Session) -> FrontmatterValue {
        var pairs: [FrontmatterValue.Pair] = [
            .init("day", .string(s.day.rawValue)), .init("time", .string(s.start.string)),
            .init("length", .number(s.lengthHours)), .init("kind", .string(s.kind))]
        if let room = s.room { pairs.append(.init("room", .string(room))) }
        return .map(pairs)
    }

    static func entry(_ e: Exam) -> FrontmatterValue {
        var pairs: [FrontmatterValue.Pair] = [.init("title", .string(e.title)), .init("date", .date(e.date))]
        if let t = e.time { pairs.append(.init("time", .string(t.string))) }
        pairs.append(.init("weight", .string("\(e.weightPercent)%")))
        return .map(pairs)
    }

    static func entry(_ g: GradingPart) -> FrontmatterValue {
        .map([.init("label", .string(g.label)), .init("weight", .string("\(g.weightPercent)%"))])
    }
}
