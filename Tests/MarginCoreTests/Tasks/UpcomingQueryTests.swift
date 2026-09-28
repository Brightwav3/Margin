import Foundation
import Testing
@testable import MarginCore

@Suite struct UpcomingQueryTests {
    typealias S = TaskQueryTestSupport
    let monday = FixedClock()   // Mon 28 Sep 2026

    private var tasks: [TaskItem] {
        [
            S.item("overdue", due: S.date(2026, 9, 27)),
            S.item("today", due: S.date(2026, 9, 28)),
            S.item("tue", due: S.date(2026, 9, 29), course: "chem"),
            S.item("tue-bio", due: S.date(2026, 9, 29), course: "bio"),
            S.item("thu", due: S.date(2026, 10, 1)),
            S.item("fri", due: S.date(2026, 10, 2)),
            S.item("sun", due: S.date(2026, 10, 4)),
            S.item("next-mon", due: S.date(2026, 10, 5)),
            S.item("december", due: S.date(2026, 12, 24)),
            S.item("next-year", due: S.date(2027, 1, 3)),
            S.item("done-tue", due: S.date(2026, 9, 29), done: true),
            S.item("done-later", due: S.date(2026, 11, 1), done: true),
            S.item("undated", due: nil),
        ]
    }

    private let exams = [S.exam("exam-b", due: S.date(2026, 10, 14)), S.exam("exam-a", due: S.date(2026, 10, 1)),
                         S.exam("exam-today", due: S.date(2026, 9, 28)), S.exam("exam-past", due: S.date(2026, 9, 1))]

    @Test func groupsIntoDaysWeekLaterAndExams() {
        let r = UpcomingQuery(clock: monday).run(tasks: tasks, exams: exams)
        #expect(r.days.map(\.date) == [S.date(2026, 9, 29), S.date(2026, 10, 1)])   // Wed 30 has none: omitted
        #expect(r.days.map { $0.items.map(\.id) } == [["tue-bio", "tue"], ["thu"]])
        #expect(r.thisWeek.map(\.id) == ["fri", "sun"])
        #expect(r.later.map(\.id) == ["next-mon", "december", "next-year"])
        #expect(r.exams.map(\.id) == ["exam-a", "exam-b"])
    }

    @Test func leavesOutDoneUndatedOverdueAndToday() {
        let r = UpcomingQuery(clock: monday).run(tasks: tasks, exams: exams)
        let all = Set(r.items.map(\.id))
        for id in ["overdue", "today", "done-tue", "done-later", "undated", "exam-today", "exam-past"] {
            #expect(!all.contains(id), "\(id)")
        }
        #expect(all.count == 8 + 2)
    }

    @Test func everyItemAppearsOnceAndFlatListIsSortedByDueDate() {
        let r = UpcomingQuery(clock: monday).run(tasks: tasks, exams: exams)
        let ids = r.items.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids == ["tue-bio", "tue", "exam-a", "thu", "fri", "sun", "next-mon", "exam-b", "december", "next-year"])
    }

    @Test func labelsAreComputedForToday() {
        let r = UpcomingQuery(clock: monday).run(tasks: tasks, exams: exams)
        #expect(r.days[0].items.map(\.label) == [.tomorrow, .tomorrow])
        #expect(r.days[1].items[0].label == .weekday(.thursday))
        #expect(r.later.last?.label == .date(S.date(2027, 1, 3)))
    }

    @Test func endOfWeekIsSunday() throws {
        // Saturday 3 Oct: tomorrow is Sunday, and the days that get their own group run into next week.
        let saturday = FixedClock(local: LocalDateTime(date: S.date(2026, 10, 3), time: .literal(9)))
        let r = UpcomingQuery(clock: saturday).run(tasks: tasks, exams: [])
        #expect(r.days.map(\.date) == [S.date(2026, 10, 4), S.date(2026, 10, 5)])
        #expect(r.thisWeek.isEmpty)
        #expect(r.later.map(\.id) == ["december", "next-year"])

        // Sunday 4 Oct: the week is over, so nothing is "this week".
        let sunday = FixedClock(local: LocalDateTime(date: S.date(2026, 10, 4), time: .literal(9)))
        let s = UpcomingQuery(clock: sunday).run(tasks: tasks, exams: [])
        #expect(s.days.map(\.date) == [S.date(2026, 10, 5)] && s.thisWeek.isEmpty)
    }

    @Test func daysAheadControlsTheDayGroups() {
        let none = UpcomingQuery(clock: monday, daysAhead: 0).run(tasks: tasks)
        #expect(none.days.isEmpty)
        #expect(none.thisWeek.map(\.id) == ["tue-bio", "tue", "thu", "fri", "sun"])
        let seven = UpcomingQuery(clock: monday, daysAhead: 7).run(tasks: tasks)
        #expect(seven.days.map(\.date).last == S.date(2026, 10, 5))
        #expect(seven.thisWeek.isEmpty)
        #expect(UpcomingQuery(clock: monday, daysAhead: -4).daysAhead == 0)
    }

    @Test func thePartitionFollowsTheClockAtMidnightAndInOtherZones() throws {
        let items = [S.item("tue", due: S.date(2026, 9, 29)), S.item("wed", due: S.date(2026, 9, 30))]
        // 23:59:59 Monday vs 00:00 Tuesday in Prague.
        let mid = try S.instant("2026-09-28T22:00:00Z")
        let before = UpcomingQuery(clock: FixedClock(now: mid.addingTimeInterval(-1))).run(tasks: items)
        #expect(before.days.map { $0.items.map(\.id) } == [["tue"], ["wed"]])
        let after = UpcomingQuery(clock: FixedClock(now: mid)).run(tasks: items)
        #expect(after.days.map { $0.items.map(\.id) } == [["wed"]])     // Tue is today now
        // The same instant in New York is still Monday evening.
        let ny = UpcomingQuery(clock: FixedClock(now: mid, timeZone: try S.zone("America/New_York"))).run(tasks: items)
        #expect(ny.days.map { $0.items.map(\.id) } == [["tue"], ["wed"]])
    }

    @Test func aTaskDueAfterTheClockChangeDayMovesAcrossDST() throws {
        // The night Prague falls back (25 Oct): Monday 26 Oct is "tomorrow" all evening.
        let c = try S.clock("2026-10-25T22:59:59Z", in: "Europe/Prague")     // 23:59:59 Sun 25 Oct
        let r = UpcomingQuery(clock: c).run(tasks: [S.item("mon", due: S.date(2026, 10, 26))])
        #expect(r.days.first?.items.first?.label == .tomorrow)
        let next = try S.clock("2026-10-25T23:00:00Z", in: "Europe/Prague")
        #expect(UpcomingQuery(clock: next).run(tasks: [S.item("mon", due: S.date(2026, 10, 26))]).days.isEmpty)
    }

    @Test func emptyInput() {
        let r = UpcomingQuery(clock: monday).run(tasks: [])
        #expect(r.days.isEmpty && r.thisWeek.isEmpty && r.later.isEmpty && r.exams.isEmpty && r.items.isEmpty)
    }
}
