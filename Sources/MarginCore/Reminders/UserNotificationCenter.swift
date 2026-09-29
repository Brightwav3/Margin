#if canImport(UserNotifications)
import Foundation
import UserNotifications

/// `ReminderCenter` on `UNUserNotificationCenter`: each reminder is a calendar-less time-interval
/// trigger request whose identifier is the occurrence id; the reminder itself travels in `userInfo`
/// so `pending()` can give it back.
///
/// UNVERIFIED: written on Linux, where `UserNotifications` does not exist, so it has never been
/// compiled or run. Needs the app's notification entitlement and a bundle.
// TODO(M10-18): verify on macOS
public struct UserNotificationCenter: ReminderCenter, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let clock: any Clock

    public init(center: UNUserNotificationCenter = .current(), clock: any Clock = SystemClock()) {
        self.center = center; self.clock = clock
    }

    public func permission() async -> ReminderPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }

    public func requestPermission() async throws -> ReminderPermission {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await permission()
    }

    public func add(_ reminders: [Reminder]) async throws {
        for r in reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            if let data = try? JSONEncoder().encode(r), let json = String(data: data, encoding: .utf8) {
                content.userInfo = ["reminder": json]
            }
            let seconds = max(1, r.fireDate.timeIntervalSince(clock.now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            try await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
    }

    public func remove(ids: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func pending() async -> [Reminder] {
        await center.pendingNotificationRequests().compactMap { request in
            guard let json = request.content.userInfo["reminder"] as? String, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Reminder.self, from: data)
        }
        .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }
}
#endif
