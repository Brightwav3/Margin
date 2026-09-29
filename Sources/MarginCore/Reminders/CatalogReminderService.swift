import Foundation

/// `ReminderService` over a `CourseCatalog` (fixture or vault) and a `ReminderCenter`.
public struct CatalogReminderService: ReminderService {
    /// Seconds before the class start (10 minutes).
    public static let leadTime: TimeInterval = 10 * 60

    private let courses: any CourseCatalog
    private let center: any ReminderCenter
    private let clock: any Clock

    public init(courses: any CourseCatalog, center: any ReminderCenter, clock: any Clock) {
        self.courses = courses; self.center = center; self.clock = clock
    }

    public var permission: ReminderPermission { get async { await center.permission() } }

    public func requestPermission() async throws -> ReminderPermission { try await center.requestPermission() }

    public func schedule(for week: Int) async throws -> [Reminder] {
        guard await center.permission() == .authorized else {
            throw MarginError.forbidden("Notifications are not allowed for Margin")
        }
        let occurrences: [SessionOccurrence]
        do { occurrences = try await courses.sessions(week: week) } catch MarginError.notFound {
            // No live semester (archived, or none): nothing to remind of.
            await cancelAll()
            return []
        }
        let now = clock.now
        var planned: [Reminder] = []
        for o in occurrences where !o.isCancelled {
            guard let starts = clock.date(from: o.start) else { continue }
            let fire = starts.addingTimeInterval(-Self.leadTime)
            guard fire > now else { continue }
            let course = try? await courses.course(id: o.session.courseID)
            planned.append(Reminder(
                id: o.id, week: week, courseID: o.session.courseID, title: course?.name ?? o.session.courseID,
                body: Self.body(for: o), start: o.start, fireDate: fire))
        }
        planned.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        let keep = Set(planned.map(\.id))
        let stale = await center.pending().filter { $0.week == week && !keep.contains($0.id) }.map(\.id)
        await center.remove(ids: stale)
        try await center.add(planned)
        return planned
    }

    public func pending() async -> [Reminder] { await center.pending() }

    public func cancel(occurrenceID: String) async { await center.remove(ids: [occurrenceID]) }

    public func cancelAll() async { await center.remove(ids: await center.pending().map(\.id)) }

    /// `Lecture at 10:00 in Sci 204`.
    static func body(for o: SessionOccurrence) -> String {
        var text = "\(o.session.kind) at \(o.session.start.string)"
        if let room = o.session.room, !room.isEmpty { text += " in \(room)" }
        return text
    }
}
