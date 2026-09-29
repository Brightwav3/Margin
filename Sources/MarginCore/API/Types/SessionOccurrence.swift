/// One concrete class on a calendar day: a weekly `Session` placed in a week of the semester.
///
/// `SessionOverride`s (cancelled, moved) are not applied yet; they arrive with
/// `CourseCatalogWriter` (M10).
public struct SessionOccurrence: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(session.id)@\(date.iso)" }
    public var session: Session
    /// The day the class takes place.
    public var date: LocalDate

    public init(session: Session, date: LocalDate) {
        self.session = session; self.date = date
    }

    /// Wall-clock start.
    public var start: LocalDateTime { LocalDateTime(date: date, time: session.start) }
}
