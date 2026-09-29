import Foundation

/// The only source of "now" in MarginCore and MarginUI (contract rule 7): never call `Date()`
/// in logic. `today` is the wall-clock calendar day in `timeZone`, so "today" and "tomorrow"
/// follow the user's local midnight, not UTC.
///
/// Only `now` and `timeZone` must be provided; everything else has a default derived from them.
public protocol Clock: Sendable {
    /// The current instant.
    var now: Date { get }
    /// Time zone that defines local midnight.
    var timeZone: TimeZone { get }
    /// Gregorian calendar in `timeZone`, weeks starting on Monday.
    var calendar: Calendar { get }
    /// Current wall-clock date and time.
    var localNow: LocalDateTime { get }
    /// Current calendar day.
    var today: LocalDate { get }
    /// 1-based week of `semester` that contains `today`, or `nil` outside the term.
    func weekOfSemester(_ semester: Semester) -> Int?
}

extension Clock {
    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    public var localNow: LocalDateTime { localDateTime(from: now) }

    public var today: LocalDate { localNow.date }

    public var tomorrow: LocalDate { today.adding(days: 1) }

    public func weekOfSemester(_ semester: Semester) -> Int? { semester.week(of: today) }

    /// Wall-clock value of an instant in this clock's time zone.
    public func localDateTime(from date: Date) -> LocalDateTime {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = LocalDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1) ?? LocalDate(daysSinceEpoch: 0)
        let time = LocalTime(hour: c.hour ?? 0, minute: c.minute ?? 0) ?? LocalTime.literal(0)
        return LocalDateTime(date: day, time: time)
    }

    /// Instant of a wall-clock value in this clock's time zone (`nil` only for nonexistent DST gaps
    /// that the calendar cannot resolve).
    public func date(from local: LocalDateTime) -> Date? {
        var c = DateComponents()
        c.year = local.date.year; c.month = local.date.month; c.day = local.date.day
        c.hour = local.time.hour; c.minute = local.time.minute
        return calendar.date(from: c)
    }
}

/// The real clock. Reads the system time on every access.
public struct SystemClock: Clock {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) { self.timeZone = timeZone }

    public var now: Date { Date() }
}

/// A frozen clock for tests, fixtures and previews. Default: Monday 28 Sep 2026, 13:24 in
/// Europe/Prague (week 5 of Fall 2026). The instant is derived from the wall-clock value and the
/// time zone, so `today` and `localNow` are identical on every host.
public struct FixedClock: Clock {
    /// Default fixture time zone.
    public static var defaultTimeZone: TimeZone {
        TimeZone(identifier: "Europe/Prague") ?? TimeZone(secondsFromGMT: 3600) ?? .gmt
    }

    /// Default fixture wall-clock time: 2026-09-28T13:24.
    public static let defaultLocal = LocalDateTime(date: .literal(2026, 9, 28), time: .literal(13, 24))

    public let timeZone: TimeZone
    public let now: Date

    public init(local: LocalDateTime = FixedClock.defaultLocal, timeZone: TimeZone = FixedClock.defaultTimeZone) {
        self.timeZone = timeZone
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        var parts = DateComponents()
        parts.year = local.date.year; parts.month = local.date.month; parts.day = local.date.day
        parts.hour = local.time.hour; parts.minute = local.time.minute
        self.now = c.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// A fixed clock at an exact instant.
    public init(now: Date, timeZone: TimeZone = FixedClock.defaultTimeZone) {
        self.now = now; self.timeZone = timeZone
    }

    /// A copy moved by `seconds` (negative goes back).
    public func advanced(bySeconds seconds: TimeInterval) -> FixedClock {
        FixedClock(now: now.addingTimeInterval(seconds), timeZone: timeZone)
    }
}
