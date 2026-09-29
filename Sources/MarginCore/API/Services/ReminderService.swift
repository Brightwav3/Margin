/// Notifications 10 minutes before each class (M10-18). Works from the timetable: what
/// `CourseCatalog.sessions(week:)` returns, so moved and cancelled classes and archived semesters
/// are already accounted for.
///
/// `CatalogReminderService` is the one implementation (it only needs a `CourseCatalog` and a
/// `ReminderCenter`, which is the platform part: `InMemoryReminderCenter` for tests and previews,
/// `UserNotificationCenter` on macOS). Rules, checked by
/// `Tests/Conformance/ReminderServiceConformanceTests.swift` against both environments:
///
/// - `schedule(for:)` plans a reminder for every class of the week that is not cancelled and whose
///   fire time (`start` minus 10 minutes, in the `Clock`'s time zone) is still in the future, and
///   replaces what was planned for that week before: a class that was moved gets its new time, a
///   cancelled or removed one loses its reminder. Nothing is shown late: a class starting within
///   10 minutes gets no reminder. Returns the reminders now planned for the week, by fire time.
/// - Without permission (`permission` is not `.authorized`) it throws `.forbidden` and plans nothing.
/// - When the vault has no live semester (all archived), every reminder is cancelled.
/// - `cancel(occurrenceID:)` and `cancelAll()` remove reminders; unknown ids are ignored.
public protocol ReminderService: Sendable {
    /// Whether notifications are allowed right now.
    var permission: ReminderPermission { get async }

    /// Asks the system for permission (the user sees a dialog the first time).
    func requestPermission() async throws -> ReminderPermission

    /// Plans the reminders of a week of the current semester.
    func schedule(for week: Int) async throws -> [Reminder]

    /// The reminders planned now, by fire time.
    func pending() async -> [Reminder]

    /// Removes the reminder of one class occurrence.
    func cancel(occurrenceID: String) async

    /// Removes all reminders.
    func cancelAll() async
}
