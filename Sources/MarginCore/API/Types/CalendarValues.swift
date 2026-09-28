import Foundation

// Calendar values used across the contract.
//
// Design choice: due dates, session days, exam dates and capture times are *wall-clock*
// values ("Thu 1 Oct", "10:00"), not instants. Storing them as `Date` would make them shift
// when the user's time zone changes (travel, DST) and would make fixtures depend on the host
// time zone. So they are plain `LocalDate` / `LocalTime` / `LocalDateTime` values, exactly as
// written in the vault (`2026-10-01`, `"10:00"`, `2026-09-28T09:12`). Converting to and from
// `Date` happens only through a `Clock`, which owns the time zone.

/// A day of the week. Raw values are the short English names used in the vault (`day: Tue`).
public enum Weekday: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case monday = "Mon", tuesday = "Tue", wednesday = "Wed", thursday = "Thu"
    case friday = "Fri", saturday = "Sat", sunday = "Sun"

    /// ISO 8601 number: Monday = 1 … Sunday = 7.
    public var isoNumber: Int {
        switch self {
        case .monday: 1
        case .tuesday: 2
        case .wednesday: 3
        case .thursday: 4
        case .friday: 5
        case .saturday: 6
        case .sunday: 7
        }
    }

    /// Tolerant parsing of `Tue`, `tue`, `tuesday`, `Tuesday`.
    public init?(token: String) {
        let lower = token.lowercased()
        guard lower.count >= 3,
              let match = Weekday.allCases.first(where: {
                  let short = $0.rawValue.lowercased()
                  return lower == short || lower == $0.fullName
              })
        else { return nil }
        self = match
    }

    /// Lowercase full English name (`tuesday`).
    public var fullName: String {
        switch self {
        case .monday: "monday"
        case .tuesday: "tuesday"
        case .wednesday: "wednesday"
        case .thursday: "thursday"
        case .friday: "friday"
        case .saturday: "saturday"
        case .sunday: "sunday"
        }
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.isoNumber < rhs.isoNumber }
}

/// A calendar day in the proleptic Gregorian calendar, without time or time zone.
///
/// Invariant: always a valid date (`month` 1…12, `day` within the month).
/// Encoded as an ISO string `YYYY-MM-DD`. Ordering is chronological.
public struct LocalDate: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns `nil` when the components do not form a valid date.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= LocalDate.daysIn(month: month, year: year)
        else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    /// Parses `YYYY-MM-DD`.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Days since 1970-01-01 (may be negative).
    public init(daysSinceEpoch z0: Int) {
        // Howard Hinnant, civil_from_days.
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.month = m
        self.day = d
    }

    /// Days since 1970-01-01.
    public var daysSinceEpoch: Int {
        // Howard Hinnant, days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public var weekday: Weekday {
        // 1970-01-01 was a Thursday (index 3 with Monday = 0).
        let index = ((daysSinceEpoch % 7) + 7 + 3) % 7
        return Weekday.allCases[index]
    }

    public func adding(days: Int) -> LocalDate { LocalDate(daysSinceEpoch: daysSinceEpoch + days) }

    /// Signed number of days from `self` to `other`.
    public func days(to other: LocalDate) -> Int { other.daysSinceEpoch - daysSinceEpoch }

    /// Monday of the ISO week containing this date.
    public var startOfWeek: LocalDate { adding(days: -(weekday.isoNumber - 1)) }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.daysSinceEpoch < rhs.daysSinceEpoch }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let v = LocalDate(iso: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date '\(s)'")
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }

    static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

/// A wall-clock time of day with minute precision.
///
/// Invariant: `hour` 0…23, `minute` 0…59. Encoded as `HH:mm`.
public struct LocalTime: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour; self.minute = minute
    }

    /// Parses `H:mm` or `HH:mm`.
    public init?(string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1])
        else { return nil }
        self.init(hour: h, minute: m)
    }

    /// Minutes since midnight, 0…1439.
    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public var string: String { String(format: "%02d:%02d", hour, minute) }
    public var description: String { string }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let v = LocalTime(string: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid time '\(s)'")
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}

/// A wall-clock date and time without a time zone (`2026-09-28T09:12`).
public struct LocalDateTime: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let date: LocalDate
    public let time: LocalTime

    public init(date: LocalDate, time: LocalTime) {
        self.date = date; self.time = time
    }

    /// Parses `YYYY-MM-DDTHH:mm`.
    public init?(iso: String) {
        let parts = iso.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2, let d = LocalDate(iso: String(parts[0])),
              let t = LocalTime(string: String(parts[1])), parts[1].count == 5
        else { return nil }
        self.init(date: d, time: t)
    }

    public var iso: String { "\(date.iso)T\(time.string)" }
    public var description: String { iso }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        (lhs.date, lhs.time) < (rhs.date, rhs.time)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let v = LocalDateTime(iso: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date-time '\(s)'")
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}

// Internal, non-failable constructors for statically known values (fixtures, tests via @testable).
extension LocalDate {
    /// Only for literals known to be valid; invalid input is clamped rather than crashing.
    static func literal(_ y: Int, _ m: Int, _ d: Int) -> LocalDate {
        LocalDate(year: y, month: m, day: d)
            ?? LocalDate(daysSinceEpoch: 0)
    }
}

extension LocalTime {
    static func literal(_ h: Int, _ m: Int = 0) -> LocalTime {
        LocalTime(hour: h, minute: m) ?? LocalTime(uncheckedMinutes: 0)
    }

    private init(uncheckedMinutes: Int) {
        self.hour = uncheckedMinutes / 60
        self.minute = uncheckedMinutes % 60
    }
}
