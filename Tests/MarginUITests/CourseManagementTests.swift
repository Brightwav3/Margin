import MarginCore
import Testing
@testable import MarginUI

/// Course settings, archive, delete and new semesters from the workspace (M10-12.U, M10-13.U).
@MainActor @Suite struct CourseManagementTests {
    private func loaded() async -> Workspace {
        let w = Workspace(env: .fixture())
        await w.courses.load()
        return w
    }

    private func settle(_ w: Workspace, until done: () -> Bool) async {
        for _ in 0..<100 where !done() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func archivingACourseHidesItAndLeavesItsPage() async throws {
        let w = await loaded()
        let bio = try #require(w.courses.course(id: "bio"))
        let count = w.courses.cards.count
        w.open(course: bio)
        #expect(w.route == .course("bio"))
        w.setCourseArchived(bio, true)
        await settle(w) { w.courses.cards.count == count - 1 }
        #expect(w.courses.cards.count == count - 1)
        #expect(w.route == .courses)
        #expect(try await w.env.courses.archivedCourses().map(\.id) == ["bio"])
        w.setCourseArchived(bio, false)
        await settle(w) { w.courses.cards.count == count }
        #expect(w.courses.cards.count == count)
    }

    @Test func courseSettingsSaveTheTimetableAndDetails() async throws {
        let w = await loaded()
        _ = try await w.env.courseWriter.update(id: "math", CourseUpdate(professor: "Doc. Novák", credits: 5,
                                                                        sessions: [NewSession(day: .thursday, start: LocalTime(hour: 8, minute: 0)!,
                                                                                              lengthHours: 1.67, kind: "Seminář", room: "S307")]),
                                                actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        await w.refreshAfterWrite()
        let math = try #require(w.courses.course(id: "math"))
        #expect(math.professor == "Doc. Novák" && math.credits == 5)
        #expect(math.sessions.map(\.kind) == ["Seminář"] && math.sessions[0].room == "S307")
        #expect(SessionEditorRow.lengthLabel(1.67) == "100 min" && SessionEditorRow.lengthLabel(2) == "2 h")
        #expect(SessionEditorRow.lengths(including: 1.25).contains(1.25))
    }

    @Test func aNewSemesterAppearsInTheSidebar() async throws {
        let w = await loaded()
        _ = try await w.env.semesters.create(NewSemester(name: "Jaro 2027", start: LocalDate(year: 2027, month: 2, day: 15)!,
                                                         end: LocalDate(year: 2027, month: 5, day: 30)!),
                                             actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        await w.refreshAfterWrite()
        #expect(w.courses.semesters.contains { $0.name == "Jaro 2027" })
        #expect(w.semestersSection.items.contains { $0.title == "Jaro 2027" })
        #expect(w.semestersSection.items.last?.title == "New semester…")
    }
}
