/// One concrete class on a calendar day: a weekly `Session` placed in a week of the semester, with the
/// `SessionOverride` of that day applied (`CourseCatalogWriter.override(session:)`).
///
/// For a moved class `session` carries the new start time and room, `date` the new day and
/// `originalDate` the day the weekly schedule had it. A cancelled class stays in the list with
/// `isCancelled` set (the UI decides how to show it). Without an override `originalDate == date`.
public struct SessionOccurrence: Codable, Sendable, Hashable, Identifiable {
    /// Stable across moves: the session and the day it was scheduled on.
    public var id: String { "\(session.id)@\(originalDate.iso)" }
    public var session: Session
    /// The day the class takes place.
    public var date: LocalDate
    /// The day the weekly schedule placed it on.
    public var originalDate: LocalDate
    public var isCancelled: Bool
    /// The reason given with the override.
    public var note: String?

    public init(session: Session, date: LocalDate, originalDate: LocalDate? = nil, isCancelled: Bool = false,
                note: String? = nil) {
        self.session = session; self.date = date; self.originalDate = originalDate ?? date
        self.isCancelled = isCancelled; self.note = note
    }

    /// `true` when the class differs from the weekly schedule (moved, other room or cancelled).
    public var isOverridden: Bool { isCancelled || originalDate != date || note != nil }

    /// Wall-clock start.
    public var start: LocalDateTime { LocalDateTime(date: date, time: session.start) }

    private enum CodingKeys: String, CodingKey { case session, date, originalDate, isCancelled, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let date = try c.decode(LocalDate.self, forKey: .date)
        self.init(session: try c.decode(Session.self, forKey: .session), date: date,
                  originalDate: try c.decodeIfPresent(LocalDate.self, forKey: .originalDate),
                  isCancelled: try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false,
                  note: try c.decodeIfPresent(String.self, forKey: .note))
    }
}
