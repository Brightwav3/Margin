import Foundation
import Testing
@testable import MarginCore

/// M10-19.B: a syllabus is written into `_course.md` as a lossless frontmatter edit.
@Suite struct SyllabusWriteTests {
    private static let handWritten = """
        ---
        # my own comment
        name: Cell Biology
        code: BIO 201
        custom-key: [1, 2, three]
        color: bio    # the green one
        icon: eco
        sessions:
          - {day: Tue, time: "10:00", length: 1.5, kind: Lecture}   # keep this spacing
        exams:
          - { title: Midterm,   date: 2026-10-01, weight: 25% }
        professor: Dr. Okafor
        ---

        # Cell Biology

        Body text stays.

        """

    private func vault() async throws -> CourseVault {
        let dir = TempDir()
        try dir.seed("Fall 2026/Cell Biology/_course.md", Data(Self.handWritten.utf8))
        try dir.seed(".margin/semesters.json", Data(SampleVaultGenerator.semestersJSON(Fixtures.week5.semester).utf8))
        return try await CourseVault.reopen(dir)
    }

    private func service(_ v: CourseVault) -> VaultSyllabusService { VaultSyllabusService(backend: v.backend) }

    @Test func onlyTheEditedSectionChanges() async throws {
        let v = try await vault()
        var draft = try await service(v).draft(course: "cell-biology")
        draft.grading = [GradingPart(label: "Exam", weightPercent: 70), GradingPart(label: "Homework", weightPercent: 30)]
        let cs = try await service(v).apply(draft, to: "cell-biology", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(cs.entries.count == 1)
        let after = v.text("Fall 2026/Cell Biology/_course.md")
        // Everything but the new `grading:` block is byte for byte what it was.
        let kept = Self.handWritten.replacingOccurrences(of: "professor: Dr. Okafor\n---\n", with: "professor: Dr. Okafor\ngrading:\n  - {label: Exam, weight: 70%}\n  - {label: Homework, weight: 30%}\n---\n")
        #expect(after == kept)
        let course = try await v.catalog.course(id: "cell-biology")
        #expect(course.grading == draft.grading && course.exams.count == 1 && course.sessions.count == 1)
        await v.shutdown()
    }

    @Test func rewritingASectionKeepsTheRestAndSurvivesARestart() async throws {
        let v = try await vault()
        let draft = SyllabusDraft(
            sessions: [NewSession(day: .friday, start: .literal(8, 30), lengthHours: 1.25, kind: "Lab", room: "Room \"B\": 2"),
                       NewSession(day: .tuesday, start: .literal(10, 0))],
            exams: [SyllabusExam(title: "Final: part 1", date: .literal(2026, 12, 11), time: .literal(9, 0), weightPercent: 40)])
        _ = try await service(v).apply(draft, to: "cell-biology", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        let after = v.text("Fall 2026/Cell Biology/_course.md")
        for kept in ["# my own comment\n", "custom-key: [1, 2, three]\n", "color: bio    # the green one\n", "professor: Dr. Okafor\n", "\n# Cell Biology\n\nBody text stays.\n"] {
            #expect(after.contains(kept))
        }
        #expect(CourseValidator.validate(after).isEmpty)
        await v.shutdown()
        let again = try await CourseVault.reopen(v.dir)
        let course = try await again.catalog.course(id: "cell-biology")
        #expect(course.sessions.map(\.id) == ["cell-biology-fri-0830", "cell-biology-tue-1000"])
        #expect(course.sessions[0].room == "Room \"B\": 2" && course.sessions[0].lengthHours == 1.25 && course.sessions[0].kind == "Lab")
        #expect(course.exams.first?.title == "Final: part 1" && course.exams.first?.time == .literal(9, 0) && course.exams.first?.weightPercent == 40)
        #expect(SyllabusDraft(course: course).sessions == draft.sessions && SyllabusDraft(course: course).exams == draft.exams)
        await again.shutdown()
    }

    @Test func anUnchangedSectionIsNotRewritten() async throws {
        let v = try await vault()
        // Same exams and sessions as the file, grading new: the hand-made spacing of the others stays.
        var draft = try await service(v).draft(course: "cell-biology")
        draft.grading = [GradingPart(label: "All", weightPercent: 100)]
        _ = try await service(v).apply(draft, to: "cell-biology", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        let after = v.text("Fall 2026/Cell Biology/_course.md")
        #expect(after.contains("{ title: Midterm,   date: 2026-10-01, weight: 25% }") && after.contains("# keep this spacing"))
        await v.shutdown()
    }

    @Test func draftHelpers() {
        #expect(SyllabusDraft().warnings.isEmpty && SyllabusDraft().gradingTotal == nil)
        #expect(SyllabusDraft(grading: [GradingPart(label: "A", weightPercent: 30)]).gradingTotal == 30)
        #expect(SyllabusDraft(sessions: []).warnings == ["The timetable is empty"])
        let data = try? JSONEncoder().encode(SyllabusDraft(sessions: [NewSession(day: .monday, start: .literal(9, 0))], exams: [], grading: nil))
        #expect(data.flatMap { try? JSONDecoder().decode(SyllabusDraft.self, from: $0) }?.sessions?.count == 1)
    }
}
