import Foundation
import Testing
@testable import MarginCore

private func codeOf<T>(_ body: () async throws -> T) async -> String? {
    do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other" }
}

private let tuesday = LocalDate.literal(2026, 9, 29)
private func at(_ day: LocalDate, _ h: Int, _ m: Int) -> LocalDateTime { LocalDateTime(date: day, time: .literal(h, m)) }

/// `ReminderService`, run against both environments (contract §5). The platform part is an
/// `InMemoryReminderCenter`; `UserNotificationCenter` is macOS only and not covered here.
@Suite struct ReminderServiceConformanceTests {
    @Test(arguments: HarnessKind.allCases)
    func plansTenMinutesBeforeEveryClassStillAhead(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            // Monday 28 Sep 13:24: the 11:00 class is over, the 14:00 lab is ahead.
            let planned = try await h.reminders.schedule(for: 5)
            #expect(planned.count == 10)
            let first = planned[0]
            #expect(first.courseID == "chem" && first.title == "Organic Chemistry" && first.body == "Lab at 14:00 in Lab C")
            #expect(first.start == at(.literal(2026, 9, 28), 14, 0) && first.week == 5)
            #expect(first.fireDate == h.clock.date(from: at(.literal(2026, 9, 28), 13, 50)))
            for r in planned { #expect(h.clock.date(from: r.start)!.timeIntervalSince(r.fireDate) == 600) }
            #expect(planned.map(\.fireDate) == planned.map(\.fireDate).sorted())
            #expect(planned.contains { $0.courseID == "bio" && $0.start == at(tuesday, 10, 0) && $0.body == "Lecture at 10:00 in Sci 204" })
            #expect(!planned.contains { $0.courseID == "math" && $0.start.date == .literal(2026, 9, 28) })
            // Scheduling again gives the same, nothing twice.
            #expect(try await h.reminders.schedule(for: 5) == planned)
            #expect(await h.reminders.pending() == planned)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aShiftedClockChangesWhatIsStillAhead(kind: HarnessKind) async throws {
        // 09:49 on Tuesday: the 10:00 lecture's reminder (09:50) is a minute away.
        try await withHarness(kind, clock: FixedClock(local: at(tuesday, 9, 49))) { h in
            let planned = try await h.reminders.schedule(for: 5)
            #expect(planned.first?.courseID == "bio" && planned.first?.start == at(tuesday, 10, 0))
            #expect(planned.first?.fireDate == h.clock.date(from: at(tuesday, 9, 50)))
            #expect(planned.count == 9)
        }
        // 09:55: it is too late for that one (nothing is shown late), the next class is econ at 15:00.
        try await withHarness(kind, clock: FixedClock(local: at(tuesday, 9, 55))) { h in
            let planned = try await h.reminders.schedule(for: 5)
            #expect(planned.first?.courseID == "econ" && planned.count == 8)
        }
        // After the week: nothing.
        try await withHarness(kind, clock: FixedClock(local: at(.literal(2026, 10, 3), 12, 0))) { h in
            let planned = try await h.reminders.schedule(for: 5)
            #expect(planned.isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func cancelledAndMovedClassesFollowTheTimetable(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            _ = try await h.reminders.schedule(for: 5)
            _ = try await h.writer.override(session: SessionOverride(sessionID: "bio-tue-1000", courseID: "bio", originalDate: tuesday, cancelled: true),
                                            actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            _ = try await h.writer.override(session: SessionOverride(sessionID: "econ-tue-1500", courseID: "econ", originalDate: tuesday,
                                                                    newStart: at(tuesday, 17, 30), newRoom: "Hall C"),
                                            actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let planned = try await h.reminders.schedule(for: 5)
            #expect(planned.count == 9)
            #expect(!planned.contains { $0.id == "bio-tue-1000@2026-09-29" })
            let moved = planned.first { $0.courseID == "econ" && $0.start.date == tuesday }
            #expect(moved?.id == "econ-tue-1500@2026-09-29" && moved?.start == at(tuesday, 17, 30) && moved?.body == "Lecture at 17:30 in Hall C")
            #expect(moved?.fireDate == h.clock.date(from: at(tuesday, 17, 20)))
            #expect(await h.reminders.pending() == planned)
            // Clearing the overrides brings both back.
            for (id, course) in [("bio-tue-1000", "bio"), ("econ-tue-1500", "econ")] {
                _ = try await h.writer.clearOverride(sessionID: id, course: course, originalDate: tuesday, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
            let back = try await h.reminders.schedule(for: 5)
            #expect(back.count == 10 && back.contains { $0.id == "bio-tue-1000@2026-09-29" })
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aWeekIsReplacedNotAppended(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let week5 = try await h.reminders.schedule(for: 5)
            let week6 = try await h.reminders.schedule(for: 6)
            #expect(week6.count == 11 && week6.allSatisfy { $0.week == 6 })
            let all = await h.reminders.pending()
            #expect(all.count == week5.count + week6.count)
            #expect(Set(all.map(\.id)).count == all.count)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func archivedSemesterHasNoReminders(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            #expect(try await h.reminders.schedule(for: 5).count == 10)
            _ = try await h.writer.setArchived(semester: "fall-2026", true, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let after = try await h.reminders.schedule(for: 5)
            #expect(after.isEmpty)
            #expect(await h.reminders.pending().isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func withoutPermissionNothingIsPlanned(kind: HarnessKind) async throws {
        for state in [ReminderPermission.denied, .notDetermined] {
            try await withHarness(kind, reminderCenter: InMemoryReminderCenter(permission: state, answerToRequest: .denied)) { h in
                #expect(await h.reminders.permission == state)
                #expect(await codeOf { try await h.reminders.schedule(for: 5) } == "forbidden")
                #expect(await h.reminders.pending().isEmpty)
            }
        }
        try await withHarness(kind, reminderCenter: InMemoryReminderCenter(permission: .notDetermined, answerToRequest: .authorized)) { h in
            let granted = try await h.reminders.requestPermission()
            #expect(granted == .authorized)
            #expect(await h.reminders.permission == .authorized)
            let planned = try await h.reminders.schedule(for: 5)
            #expect(planned.count == 10)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func cancelRemovesReminders(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let planned = try await h.reminders.schedule(for: 5)
            await h.reminders.cancel(occurrenceID: planned[0].id)
            await h.reminders.cancel(occurrenceID: "nope@2026-01-01")
            #expect(await h.reminders.pending().count == planned.count - 1)
            await h.reminders.cancelAll()
            #expect(await h.reminders.pending().isEmpty)
            #expect(await codeOf { try await h.reminders.schedule(for: 99) } == "invalid")
        }
    }
}
