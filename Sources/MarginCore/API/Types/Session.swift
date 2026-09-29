/// A recurring weekly class (`sessions: - {day: Tue, time: "10:00", length: 1.5, kind: Lecture}`).
///
/// Times are wall-clock (`LocalTime`), never instants, so they do not move with the time zone.
/// `id` is `<course>-<day>-<HHmm>` and is stable while day/time are unchanged.
public struct Session: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var courseID: CourseID
    public var day: Weekday
    public var start: LocalTime
    /// Duration in hours as written in the vault (1.5 = 90 minutes). Always > 0.
    public var lengthHours: Double
    /// `Lecture`, `Lab`, `Seminar`, `Tutorial` (free text, vault is tolerant).
    public var kind: String
    public var room: String?

    public init(courseID: CourseID, day: Weekday, start: LocalTime, lengthHours: Double, kind: String, room: String? = nil) {
        self.id = "\(courseID)-\(day.rawValue.lowercased())-\(String(format: "%02d%02d", start.hour, start.minute))"
        self.courseID = courseID; self.day = day; self.start = start
        self.lengthHours = lengthHours; self.kind = kind; self.room = room
    }

    /// Length in whole minutes.
    public var lengthMinutes: Int { Int((lengthHours * 60).rounded()) }

    /// End time, clamped to 23:59 (sessions do not cross midnight).
    public var end: LocalTime {
        let m = min(start.minutesSinceMidnight + lengthMinutes, 23 * 60 + 59)
        return LocalTime(hour: m / 60, minute: m % 60) ?? start
    }
}

/// A change to a single occurrence of a `Session` (cancelled, moved, other room).
///
/// Invariant: `originalDate.weekday == session.day`. A cancelled occurrence ignores `newStart`.
public struct SessionOverride: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(sessionID)@\(originalDate.iso)" }
    public var sessionID: String
    public var courseID: CourseID
    /// The date of the occurrence being overridden.
    public var originalDate: LocalDate
    public var cancelled: Bool
    public var newStart: LocalDateTime?
    public var newRoom: String?
    public var note: String?

    public init(
        sessionID: String, courseID: CourseID, originalDate: LocalDate, cancelled: Bool = false,
        newStart: LocalDateTime? = nil, newRoom: String? = nil, note: String? = nil
    ) {
        self.sessionID = sessionID; self.courseID = courseID; self.originalDate = originalDate
        self.cancelled = cancelled; self.newStart = newStart; self.newRoom = newRoom; self.note = note
    }
}
