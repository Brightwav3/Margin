import Foundation
import MarginCore
import Testing
@testable import MarginUI

/// The app's screen models on a real vault folder: a new user's first steps survive a reopen.
@MainActor @Suite(.serialized) struct VaultIntegrationTests {
    @Test func firstRunOnAnEmptyVaultPersistsAcrossReopen() async throws {
        let clock = FixedClock()
        let scratch = try await AppEnvironment.scratchVault(clock: clock)
        let url = scratch.url
        defer { AppEnvironment.removeScratchVault(at: url) }
        var env = scratch.env
        let workspace = Workspace(env: env, vaultURL: url)
        await workspace.courses.load()
        #expect(workspace.needsOnboarding)

        // Onboarding: semester, then a course with a weekly lecture.
        _ = try await env.semesters.create(NewSemester(name: "Fall 2026", start: LocalDate(year: 2026, month: 8, day: 31)!,
                                                       end: LocalDate(year: 2026, month: 12, day: 13)!),
                                           actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        _ = try await env.courseWriter.create(NewCourse(name: "Cell Biology", semester: "fall-2026", code: "BIO 201",
                                                        icon: "eco", color: "bio",
                                                        sessions: [NewSession(day: .tuesday, start: LocalTime(hour: 10, minute: 0)!)]),
                                              actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        workspace.finishOnboarding()
        await workspace.courses.load()
        let course = try #require(workspace.courses.cards.first?.course)
        #expect(course.name == "Cell Biology")
        #expect(workspace.courses.cards.first?.next?.hasPrefix("Tue 10:00") == true)

        // A note with a task, written through the editor model.
        let detail = workspace.courseModel(course.id)
        await detail.load()
        let note = try #require(try await detail.createNote(title: "Osmosis"))
        let editor = NoteEditorModel(env: env, target: .note(note.id))
        await editor.load()
        editor.edit(editor.text + "Water follows solutes.\n\n- [ ] Redraw the diagram @2026-09-29\n")
        await editor.flush()

        // Quick capture into the course and the inbox, and a grade.
        let capture = CaptureModel(env: env)
        capture.open(prefill: "Read chapter 6 for bio")
        await capture.prepare()
        await capture.save()
        let inbox = CaptureModel(env: env)
        inbox.open(prefill: "Print the lab safety form")
        await inbox.prepare()
        inbox.dropped.insert(.course)
        await inbox.save()
        _ = try await env.grades.add(Grade(id: "g1", courseID: course.id, item: "Problem set 1", weightPercent: 10, score: 18, max: 20),
                                     actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        await env.shutdown()

        // Reopen the folder: everything is on disk.
        env = try await AppEnvironment.vault(at: url, clock: clock, watchInterval: 0.05)
        defer { Task { await env.shutdown() } }
        let again = Workspace(env: env, vaultURL: url)
        await again.courses.load()
        #expect(!again.needsOnboarding)
        #expect(again.courses.cards.map(\.course.name) == ["Cell Biology"])
        let reopened = try await env.notes.open(id: note.id)
        #expect(reopened.text.contains("Water follows solutes."))
        let tasks = try await env.tasks.tasks(course: course.id)
        #expect(tasks.contains { $0.text.contains("Redraw the diagram") && $0.due == LocalDate(year: 2026, month: 9, day: 29) })
        #expect(tasks.contains { $0.text.contains("Read chapter 6") })
        #expect(try await env.inbox.items().contains { $0.text.contains("lab safety form") })
        #expect(try await env.grades.average(course: course.id) != nil)

        let today = TasksModel(env: env, scope: .upcoming)
        await today.load()
        #expect(today.groups.flatMap(\.tasks).contains { $0.text.contains("Redraw the diagram") })
    }
}
