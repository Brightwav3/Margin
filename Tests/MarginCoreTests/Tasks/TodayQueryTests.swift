import Foundation
import Testing
@testable import MarginCore

@Suite struct TodayQueryTests {
    typealias S = TaskQueryTestSupport
    // Monday 28 Sep 2026, 13:24 in Prague.
    let clock = FixedClock()

    private var tasks: [TaskItem] {
        [
            S.item("late-old", due: S.date(2026, 9, 20), course: "phil"),
            S.item("late-new", due: S.date(2026, 9, 27), course: "bio"),
            S.item("today-b", due: S.date(2026, 9, 28), course: "math"),
            S.item("today-a", due: S.date(2026, 9, 28), course: "bio"),
            S.item("done-today", due: S.date(2026, 9, 28), done: true),
            S.item("done-late", due: S.date(2026, 9, 1), done: true),
            S.item("undated", due: nil),
            S.item("tomorrow", due: S.date(2026, 9, 29)),
        ]
    }

    @Test func splitsOverdueAndTodayAndSortsThem() {
        let r = TodayQuery(clock: clock).run(tasks: tasks)
        #expect(r.overdue.map(\.id) == ["late-old", "late-new"])
        #expect(r.today.map(\.id) == ["today-a", "today-b"])          // course id: bio < math
        #expect(r.items.map(\.id) == ["late-old", "late-new", "today-a", "today-b"])
        #expect(r.overdue.map(\.label) == [.overdue(days: 8), .overdue(days: 1)])
        #expect(r.today.map(\.label) == [.today, .today])
    }

    @Test func examsCountOnlyOnTheirDay() {
        let exams = [S.exam("exam-today", due: S.date(2026, 9, 28)), S.exam("exam-past", due: S.date(2026, 9, 27)),
                     S.exam("exam-next", due: S.date(2026, 9, 29))]
        let r = TodayQuery(clock: clock).run(tasks: tasks, exams: exams)
        #expect(r.today.map(\.id).contains("exam-today"))
        #expect(!r.items.contains { $0.id == "exam-past" || $0.id == "exam-next" })
    }

    @Test func emptyInputGivesEmptyResult() {
        let r = TodayQuery(clock: clock).run(tasks: [])
        #expect(r.overdue.isEmpty && r.today.isEmpty && r.sessions.isEmpty && r.items.isEmpty)
    }

    // MARK: Midnight

    @Test func dayChangesExactlyAtLocalMidnight() throws {
        let midnight = try S.instant("2026-09-28T22:00:00Z")     // 00:00 Tue 29 Sep in Prague (UTC+2)
        let before = FixedClock(now: midnight.addingTimeInterval(-1), timeZone: FixedClock.defaultTimeZone)
        let after = FixedClock(now: midnight, timeZone: FixedClock.defaultTimeZone)
        let items = [S.item("a", due: S.date(2026, 9, 28)), S.item("b", due: S.date(2026, 9, 29))]

        let r1 = TodayQuery(clock: before).run(tasks: items)
        #expect(r1.overdue.isEmpty && r1.today.map(\.id) == ["a"])
        let r2 = TodayQuery(clock: after).run(tasks: items)
        #expect(r2.overdue.map(\.id) == ["a"] && r2.today.map(\.id) == ["b"])
        #expect(r2.overdue.first?.label == .overdue(days: 1))
    }

    @Test func sessionsFollowTheDayAtMidnight() throws {
        let world = Fixtures.week5
        let sundayEnd = try S.clock("2026-10-04T21:59:59Z", in: "Europe/Prague")   // 23:59:59 Sun 4 Oct
        let mondayStart = try S.clock("2026-10-04T22:00:00Z", in: "Europe/Prague")  // 00:00 Mon 5 Oct
        let sunday = TodayQuery(clock: sundayEnd).sessionsToday(semesters: [world.semester], courses: world.courses)
        #expect(sunday.isEmpty)
        let monday = TodayQuery(clock: mondayStart).sessionsToday(semesters: [world.semester], courses: world.courses)
        #expect(monday.map(\.session.id) == ["math-mon-1100", "chem-mon-1400"])
        #expect(monday.allSatisfy { $0.date == S.date(2026, 10, 5) })
    }

    // MARK: Time zones

    @Test func sameInstantIsADifferentDayInDifferentZones() throws {
        let instant = try S.instant("2026-09-28T23:30:00Z")
        let items = [S.item("mon", due: S.date(2026, 9, 28)), S.item("tue", due: S.date(2026, 9, 29))]
        let expectations: [(String, [String], [String])] = [
            ("Europe/Prague", ["mon"], ["tue"]),          // 01:30 Tue 29
            ("America/New_York", [], ["mon"]),            // 19:30 Mon 28
            ("Pacific/Auckland", ["mon"], ["tue"]),       // 12:30 Tue 29 (NZDT)
            ("UTC", [], ["mon"]),                         // 23:30 Mon 28
        ]
        for (zone, overdue, today) in expectations {
            let c = FixedClock(now: instant, timeZone: try S.zone(zone))
            let r = TodayQuery(clock: c).run(tasks: items)
            #expect(r.overdue.map(\.id) == overdue, "overdue in \(zone)")
            #expect(r.today.map(\.id) == today, "today in \(zone)")
        }
    }

    @Test func travellingBackwardsAcrossTheDateLineMovesTodayBack() throws {
        let instant = try S.instant("2026-09-28T20:00:00Z")
        let auckland = FixedClock(now: instant, timeZone: try S.zone("Pacific/Auckland"))   // Tue 29 09:00
        let honolulu = FixedClock(now: instant, timeZone: try S.zone("Pacific/Honolulu"))   // Mon 28 10:00
        #expect(auckland.today == S.date(2026, 9, 29))
        #expect(honolulu.today == S.date(2026, 9, 28))
        let items = [S.item("mon", due: S.date(2026, 9, 28))]
        #expect(TodayQuery(clock: auckland).run(tasks: items).overdue.count == 1)
        #expect(TodayQuery(clock: honolulu).run(tasks: items).today.count == 1)
    }

    // MARK: DST

    @Test func autumnDayWith25HoursIsOneDay() throws {
        // Prague falls back on Sun 25 Oct 2026: that day runs 22:00Z (24th) to 23:00Z (25th).
        let items = [S.item("oct25", due: S.date(2026, 10, 25)), S.item("oct26", due: S.date(2026, 10, 26))]
        let probes: [(String, LocalDate)] = [
            ("2026-10-24T21:59:59Z", S.date(2026, 10, 24)),
            ("2026-10-24T22:00:00Z", S.date(2026, 10, 25)),
            ("2026-10-25T00:30:00Z", S.date(2026, 10, 25)),     // 02:30 CEST
            ("2026-10-25T01:30:00Z", S.date(2026, 10, 25)),     // 02:30 CET again
            ("2026-10-25T22:59:59Z", S.date(2026, 10, 25)),     // 23:59:59 CET
            ("2026-10-25T23:00:00Z", S.date(2026, 10, 26)),
        ]
        for (iso, day) in probes {
            let c = try S.clock(iso, in: "Europe/Prague")
            #expect(c.today == day, "\(iso)")
            let r = TodayQuery(clock: c).run(tasks: items)
            let expectedToday = items.filter { $0.due == day }.map(\.id)
            #expect(r.today.map(\.id) == expectedToday, "\(iso)")
        }
    }

    @Test func springDayWith23HoursIsOneDay() throws {
        // Prague springs forward on Sun 29 Mar 2026: that day runs 23:00Z (28th) to 22:00Z (29th).
        let probes: [(String, LocalDate)] = [
            ("2026-03-28T22:59:59Z", S.date(2026, 3, 28)),
            ("2026-03-28T23:00:00Z", S.date(2026, 3, 29)),
            ("2026-03-29T00:59:59Z", S.date(2026, 3, 29)),      // 01:59:59 CET
            ("2026-03-29T01:00:00Z", S.date(2026, 3, 29)),      // 03:00 CEST
            ("2026-03-29T21:59:59Z", S.date(2026, 3, 29)),
            ("2026-03-29T22:00:00Z", S.date(2026, 3, 30)),
        ]
        for (iso, day) in probes {
            #expect(try S.clock(iso, in: "Europe/Prague").today == day, "\(iso)")
        }
    }

    @Test func overdueDaysAreCalendarDaysAcrossDST() throws {
        let c = try S.clock("2026-10-26T09:00:00Z", in: "Europe/Prague")     // Mon 26 Oct, after the fall-back
        let r = TodayQuery(clock: c).run(tasks: [S.item("a", due: S.date(2026, 10, 24)), S.item("b", due: S.date(2026, 10, 25))])
        #expect(r.overdue.map(\.label) == [.overdue(days: 2), .overdue(days: 1)])
    }

    @Test func sessionsOnADSTDayKeepTheirWallClockStart() throws {
        // Add a Sunday class so the 25-hour day has one; its start is a wall-clock time.
        var world = Fixtures.week5
        world.semester = Semester(id: world.semester.id, name: world.semester.name,
                                  start: S.date(2026, 8, 31), end: S.date(2026, 12, 13))
        let session = Session(courseID: "bio", day: .sunday, start: .literal(2, 30), lengthHours: 1, kind: "Lab")
        var bio = world.courses[0]
        bio.sessions.append(session)
        let c = try S.clock("2026-10-25T01:30:00Z", in: "Europe/Prague")
        let r = TodayQuery(clock: c).sessionsToday(semesters: [world.semester], courses: [bio])
        #expect(r.map(\.session.id) == [session.id])
        #expect(r.first?.start == LocalDateTime(date: S.date(2026, 10, 25), time: .literal(2, 30)))
    }

    // MARK: Sessions

    @Test func sessionsTodayAreSortedAndOutsideTheTermThereAreNone() throws {
        let world = Fixtures.week5
        let q = TodayQuery(clock: clock)
        let today = q.sessionsToday(semesters: [world.semester], courses: world.courses)
        #expect(today.map(\.session.id) == ["math-mon-1100", "chem-mon-1400"])
        let summer = try S.clock("2026-07-15T10:00:00Z", in: "Europe/Prague")
        #expect(TodayQuery(clock: summer).sessionsToday(semesters: [world.semester], courses: world.courses).isEmpty)
        #expect(q.sessionsToday(semesters: [], courses: world.courses).isEmpty)
    }

    @Test func runKeepsOnlyTodaysSessions() throws {
        let world = Fixtures.week5
        let week = try ServiceRules.occurrences(week: 5, semester: world.semester, courses: world.courses)
        #expect(week.count > 4)
        let r = TodayQuery(clock: clock).run(tasks: [], sessions: week.reversed())
        #expect(r.sessions.map(\.session.id) == ["math-mon-1100", "chem-mon-1400"])
    }
}
