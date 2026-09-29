import Foundation
import Testing
@testable import MarginCore

private func codeOf<T>(_ body: () async throws -> T) async -> String? {
    do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other" }
}

/// `SyllabusService`, run against both environments (contract §5).
@Suite struct SyllabusServiceConformanceTests {
    @Test(arguments: HarnessKind.allCases)
    func theDraftSaysWhatTheCourseSays(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let course = try await h.courses.course(id: "bio")
            let draft = try await h.syllabus.draft(course: "bio")
            #expect(draft == SyllabusDraft(course: course))
            #expect(draft.sessions?.map(\.day) == [.tuesday, .thursday] && draft.exams?.count == 1 && draft.grading?.count == 4)
            #expect(draft.gradingTotal == 100 && draft.warnings.isEmpty)
            #expect(await codeOf { try await h.syllabus.draft(course: "nope") } == "notFound")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func editingADraftAndSavingChangesTheCourse(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let version = try await h.writer.courseVersion(id: "bio")
            var draft = try await h.syllabus.draft(course: "bio")
            draft.sessions?.append(NewSession(day: .wednesday, start: .literal(15, 30), lengthHours: 2, kind: "Lab", room: "Lab 3"))
            draft.exams?.append(SyllabusExam(title: "Final exam", date: .literal(2026, 12, 11), time: .literal(9, 0), weightPercent: 30))
            draft.grading = [GradingPart(label: "Problem sets", weightPercent: 20), GradingPart(label: "Lab reports", weightPercent: 20),
                             GradingPart(label: "Midterm", weightPercent: 30), GradingPart(label: "Final exam", weightPercent: 30)]
            let updates = h.courses.updates
            let cs = try await h.syllabus.apply(draft, to: "bio", actor: testActor, baseVersion: version, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .modified && cs.entries[0].beforeHash == version && cs.actor == testActor)
            #expect(try await h.writer.courseVersion(id: "bio") == cs.entries[0].afterHash)

            let course = try await h.courses.course(id: "bio")
            #expect(course.sessions.map(\.id) == ["bio-tue-1000", "bio-thu-1000", "bio-wed-1530"])
            #expect(course.sessions[2].lengthHours == 2 && course.sessions[2].kind == "Lab" && course.sessions[2].room == "Lab 3")
            #expect(course.exams.map(\.title) == ["Midterm", "Final exam"])
            #expect(course.exams[1].date == .literal(2026, 12, 11) && course.exams[1].time == .literal(9, 0) && course.exams[1].weightPercent == 30)
            #expect(course.grading == draft.grading)
            #expect(await next(from: updates, where: { $0.courses.contains("bio") }) != nil)
            // The timetable and Today/Upcoming see it.
            let week = try await h.courses.sessions(week: 5)
            #expect(week.contains { $0.id == "bio-wed-1530@2026-09-30" })
            // And the draft read back is the draft saved.
            #expect(try await h.syllabus.draft(course: "bio") == draft)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func missingSectionsStayAndEmptyOnesClear(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.courses.course(id: "bio")
            _ = try await h.syllabus.apply(SyllabusDraft(exams: []), to: "bio", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let after = try await h.courses.course(id: "bio")
            #expect(after.exams.isEmpty && after.sessions == before.sessions && after.grading == before.grading)
            _ = try await h.syllabus.apply(SyllabusDraft(grading: []), to: "bio", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(try await h.courses.course(id: "bio").grading.isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aDraftThatChangesNothingIsEmpty(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let version = try await h.writer.courseVersion(id: "bio")
            let draft = try await h.syllabus.draft(course: "bio")
            let cs = try await h.syllabus.apply(draft, to: "bio", actor: .user, baseVersion: version, dryRun: false, idempotencyKey: nil)
            #expect(cs.isEmpty)
            #expect(try await h.writer.courseVersion(id: "bio") == version)
            let empty = try await h.syllabus.apply(SyllabusDraft(), to: "bio", actor: .user, baseVersion: version, dryRun: false, idempotencyKey: nil)
            #expect(empty.isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func writeContext(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let version = try await h.writer.courseVersion(id: "bio")
            let draft = SyllabusDraft(exams: [SyllabusExam(title: "Quiz", date: .literal(2026, 11, 2), weightPercent: 5)])
            let dry = try await h.syllabus.apply(draft, to: "bio", actor: testActor, baseVersion: version, dryRun: true, idempotencyKey: nil)
            #expect(dry.isDryRun && dry.entries.count == 1)
            #expect(try await h.writer.courseVersion(id: "bio") == version)
            #expect(try await h.courses.course(id: "bio").exams.count == 1)
            #expect(await codeOf { try await h.syllabus.apply(draft, to: "bio", actor: .user, baseVersion: "stale", dryRun: false, idempotencyKey: nil) } == "conflict")
            let a = try await h.syllabus.apply(draft, to: "bio", actor: testActor, baseVersion: version, dryRun: false, idempotencyKey: "k")
            let b = try await h.syllabus.apply(draft, to: "bio", actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: "k")
            #expect(a == b && a.entries == dry.entries)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func invalidDraftsWriteNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let version = try await h.writer.courseVersion(id: "bio")
            let exam = SyllabusExam(title: "Quiz", date: .literal(2026, 11, 2), weightPercent: 5)
            let bad: [SyllabusDraft] = [
                SyllabusDraft(sessions: [NewSession(day: .monday, start: .literal(9, 0), lengthHours: 0)]),
                SyllabusDraft(sessions: [NewSession(day: .monday, start: .literal(9, 0), lengthHours: 13)]),
                SyllabusDraft(sessions: [NewSession(day: .monday, start: .literal(9, 0)), NewSession(day: .monday, start: .literal(9, 0), kind: "Lab")]),
                SyllabusDraft(exams: [SyllabusExam(title: " ", date: .literal(2026, 11, 2), weightPercent: 5)]),
                SyllabusDraft(exams: [SyllabusExam(title: "Q", date: .literal(2026, 11, 2), weightPercent: 101)]),
                SyllabusDraft(exams: [exam, exam]),
                SyllabusDraft(grading: [GradingPart(label: "", weightPercent: 10)]),
                SyllabusDraft(grading: [GradingPart(label: "A", weightPercent: -1)]),
                SyllabusDraft(grading: [GradingPart(label: "A", weightPercent: 50), GradingPart(label: "a", weightPercent: 20)]),
                SyllabusDraft(grading: [GradingPart(label: "A", weightPercent: 60), GradingPart(label: "B", weightPercent: 50)]),
            ]
            for draft in bad {
                #expect(await codeOf { try await h.syllabus.apply(draft, to: "bio", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "invalid")
            }
            #expect(await codeOf { try await h.syllabus.apply(SyllabusDraft(exams: [exam]), to: "nope", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "notFound")
            #expect(try await h.writer.courseVersion(id: "bio") == version)
            // Weights that do not add up are a warning for the user, not an error.
            let partial = SyllabusDraft(grading: [GradingPart(label: "Exam", weightPercent: 60)])
            #expect(partial.warnings.count == 1)
            let cs = try await h.syllabus.apply(partial, to: "bio", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries.count == 1)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func archivedSemesterIsReadOnly(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let draft = SyllabusDraft(exams: [])
            #expect(await codeOf { try await h.syllabus.apply(draft, to: "bio", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == "readOnly")
        }
    }
}
