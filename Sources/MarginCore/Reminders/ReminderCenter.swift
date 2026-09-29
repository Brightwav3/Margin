import Foundation

/// The platform side of `ReminderService`: where planned notifications are kept and shown.
public protocol ReminderCenter: Sendable {
    func permission() async -> ReminderPermission
    func requestPermission() async throws -> ReminderPermission
    /// Adds reminders; one with the id of an existing reminder replaces it.
    func add(_ reminders: [Reminder]) async throws
    func remove(ids: [String]) async
    /// Planned reminders, by fire time then id.
    func pending() async -> [Reminder]
}

/// Keeps reminders in memory and shows nothing. For tests, previews and the fixture environment.
public actor InMemoryReminderCenter: ReminderCenter {
    private var state: ReminderPermission
    private let answer: ReminderPermission
    private var reminders: [String: Reminder] = [:]

    /// - Parameters:
    ///   - permission: the permission at the start.
    ///   - answerToRequest: what `requestPermission` results in when the state is `.notDetermined`.
    public init(permission: ReminderPermission = .authorized, answerToRequest: ReminderPermission = .authorized) {
        state = permission; answer = answerToRequest
    }

    public func permission() -> ReminderPermission { state }

    public func requestPermission() -> ReminderPermission {
        if state == .notDetermined { state = answer }
        return state
    }

    public func add(_ new: [Reminder]) {
        for r in new { reminders[r.id] = r }
    }

    public func remove(ids: [String]) {
        for id in ids { reminders[id] = nil }
    }

    public func pending() -> [Reminder] {
        reminders.values.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }
}
