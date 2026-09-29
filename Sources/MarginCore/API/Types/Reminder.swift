import Foundation

/// Whether the app may show notifications.
public enum ReminderPermission: String, Codable, Sendable, Hashable {
    /// Not asked yet (`ReminderService.requestPermission` asks).
    case notDetermined
    case denied
    case authorized
}

/// A notification planned for one class: "Cell Biology, Lecture at 10:00 in Sci 204", shown 10
/// minutes before the class starts.
public struct Reminder: Codable, Sendable, Hashable, Identifiable {
    /// The id of the class occurrence (`SessionOccurrence.id`): stable when the class is moved.
    public let id: String
    /// The week of the semester it was planned for (`CourseCatalog.sessions(week:)`).
    public var week: Int
    public var courseID: CourseID
    /// Course name.
    public var title: String
    /// `Lecture at 10:00 in Sci 204`.
    public var body: String
    /// When the class starts (wall-clock).
    public var start: LocalDateTime
    /// When the notification is shown: `start` minus the lead time.
    public var fireDate: Date

    public init(id: String, week: Int, courseID: CourseID, title: String, body: String, start: LocalDateTime, fireDate: Date) {
        self.id = id; self.week = week; self.courseID = courseID; self.title = title
        self.body = body; self.start = start; self.fireDate = fireDate
    }
}
