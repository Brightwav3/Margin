import Foundation
import Testing
@testable import MarginCore

private let fall = Semester(id: "fall-2026", name: "Fall 2026",
                            start: .literal(2026, 8, 31), end: .literal(2026, 12, 13))

@Suite struct ClockConformanceTests {
    @Test func defaultFixedClockIsMondayWeek5() {
        let clock = FixedClock()
        #expect(clock.today == .literal(2026, 9, 28))
        #expect(clock.tomorrow == .literal(2026, 9, 29))
        #expect(clock.localNow.time == .literal(13, 24))
        #expect(clock.today.weekday == .monday)
        #expect(clock.weekOfSemester(fall) == 5)
        #expect(clock.timeZone.identifier == "Europe/Prague")
    }

    @Test func todayFollowsTimeZoneNotUTC() {
        // 00:30 local in Prague on 29 Sep is still 28 Sep in UTC.
        let late = FixedClock(local: LocalDateTime(date: .literal(2026, 9, 29), time: .literal(0, 30)))
        #expect(late.today == .literal(2026, 9, 29))
        let utc = FixedClock(now: late.now, timeZone: .gmt)
        #expect(utc.today == .literal(2026, 9, 28))
        let tokyo = FixedClock(now: late.now, timeZone: TimeZone(secondsFromGMT: 9 * 3600) ?? .gmt)
        #expect(tokyo.today == .literal(2026, 9, 29))
    }

    @Test func midnightBoundary() {
        let before = FixedClock(local: LocalDateTime(date: .literal(2026, 9, 28), time: .literal(23, 59)))
        #expect(before.today == .literal(2026, 9, 28))
        #expect(before.advanced(bySeconds: 60).today == .literal(2026, 9, 29))
        #expect(before.advanced(bySeconds: 60).localNow.time == .literal(0, 0))
    }

    @Test func weekOfSemesterEdges() {
        func week(_ y: Int, _ m: Int, _ d: Int) -> Int? {
            FixedClock(local: LocalDateTime(date: .literal(y, m, d), time: .literal(12, 0))).weekOfSemester(fall)
        }
        #expect(week(2026, 8, 30) == nil)
        #expect(week(2026, 8, 31) == 1)
        #expect(week(2026, 9, 6) == 1)
        #expect(week(2026, 9, 7) == 2)
        #expect(week(2026, 12, 13) == 15)
        #expect(week(2026, 12, 14) == nil)
    }

    @Test func dstDayStaysConsistent() {
        // 25 Oct 2026 is the end of DST in Prague (25 hours long); the day must not shift.
        let c = FixedClock(local: LocalDateTime(date: .literal(2026, 10, 25), time: .literal(12, 0)))
        #expect(c.today == .literal(2026, 10, 25))
        #expect(c.advanced(bySeconds: 12 * 3600).today == .literal(2026, 10, 26))
    }

    @Test func roundTripsLocalValues() {
        let clock = FixedClock()
        let local = LocalDateTime(date: .literal(2026, 10, 1), time: .literal(10, 0))
        #expect(clock.date(from: local).map { clock.localDateTime(from: $0) } == local)
    }

    @Test func systemClockIsUsable() {
        let s = SystemClock(timeZone: .gmt)
        #expect(s.today.year >= 2026)
    }
}
