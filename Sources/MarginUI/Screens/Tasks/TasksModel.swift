import MarginCore
import Observation
import SwiftUI

/// Today and Upcoming (M7, **proposal** in the spirit of Things 3: the mockups have no task screens).
@MainActor @Observable
public final class TasksModel {
    public enum Scope: Sendable { case today, upcoming }

    public struct Group: Identifiable, Sendable {
        public var id: String
        public var title: String
        /// „Mon 5 Oct“ next to a day heading.
        public var detail: String?
        public var tasks: [TaskItem]
        public var isUrgent = false
    }

    public let scope: Scope
    /// Course filter from the sidebar; nil = all.
    public var course: CourseID?
    public private(set) var tasks: [TaskItem] = []
    /// Classes of today (Today) with their course.
    public private(set) var sessions: [SessionOccurrence] = []
    public private(set) var isLoaded = false
    /// Done in this visit: stays in the list (struck) until the page reloads, like Things.
    public private(set) var justDone: Set<String> = []

    private let env: AppEnvironment

    public init(env: AppEnvironment, scope: Scope) {
        self.env = env
        self.scope = scope
    }

    var today: LocalDate { env.clock.today }

    public func load() async {
        do {
            switch scope {
            case .today:
                tasks = try await env.tasks.today()
                let semesters = try await env.courses.semesters()
                let semester = semesters.first { $0.start <= today && today <= $0.end } ?? semesters.last
                if let week = semester.flatMap({ env.clock.weekOfSemester($0) }) {
                    sessions = try await env.courses.sessions(week: week)
                        .filter { $0.date == today && !$0.isCancelled }
                        .sorted { $0.start < $1.start }
                }
            case .upcoming:
                tasks = try await env.tasks.upcoming()
            }
        } catch {
            tasks = []
        }
        isLoaded = true
    }

    public func observe() async {
        for await _ in env.tasks.updates { await load() }
    }

    private var visible: [TaskItem] {
        let kept = tasks.filter { course == nil || $0.source.courseID == course }
        return kept.sorted { a, b in
            if a.due != b.due { return (a.due ?? .init(daysSinceEpoch: .max)) < (b.due ?? .init(daysSinceEpoch: .max)) }
            if a.kind != b.kind { return a.kind == .exam }
            return a.text < b.text
        }
    }

    /// Today: Overdue, Today. Upcoming: Tomorrow, each day of the next week, Later; exams stay in their day.
    public var groups: [Group] {
        switch scope {
        case .today:
            let overdue = visible.filter { ($0.due ?? today) < today }
            let due = visible.filter { ($0.due ?? today) >= today }
            var result: [Group] = []
            if !overdue.isEmpty { result.append(Group(id: "overdue", title: "Overdue", tasks: overdue, isUrgent: true)) }
            result.append(Group(id: "today", title: "Today", tasks: due))
            return result
        case .upcoming:
            var byDay: [LocalDate: [TaskItem]] = [:]
            var later: [TaskItem] = []
            for task in visible {
                guard let due = task.due else { later.append(task); continue }
                if today.days(to: due) <= 7 { byDay[due, default: []].append(task) } else { later.append(task) }
            }
            var result = (1...7).compactMap { offset -> Group? in
                let day = today.adding(days: offset)
                guard let tasks = byDay[day] else { return nil }
                let title = offset == 1 ? "Tomorrow" : CoursesFormat.weekdayName(day.weekday)
                return Group(id: day.iso, title: title, detail: CourseDetailModel.day(day), tasks: tasks, isUrgent: offset == 1)
            }
            if !later.isEmpty { result.append(Group(id: "later", title: "Later", tasks: later)) }
            return result
        }
    }

    public var count: Int { visible.filter { !$0.done }.count }

    /// Exams in the upcoming list (right column of Upcoming).
    public var exams: [TaskItem] { visible.filter { $0.kind == .exam } }

    public func toggle(_ task: TaskItem) async throws {
        _ = try await env.tasks.toggle(id: task.id, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        if task.done { justDone.remove(task.id) } else { justDone.insert(task.id) }
        // Keep the row, struck through, until the next visit.
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].done.toggle() }
    }

    public func setDue(_ task: TaskItem, _ due: LocalDate?) async throws {
        _ = try await env.tasks.setDue(id: task.id, due: due, actor: .user, baseVersion: nil, dryRun: false,
                                       idempotencyKey: nil)
        await load()
    }
}

extension CoursesFormat {
    static func weekdayName(_ day: Weekday) -> String { day.fullName.capitalized }
}
