import MarginCore
import SwiftUI

/// Sidebar of Today and Upcoming: the places and a course filter with open counts.
extension Workspace {
    func tasksModel(_ scope: TasksModel.Scope) -> TasksModel {
        model(scope == .today ? "today" : "upcoming") { TasksModel(env: env, scope: scope) }
    }

    func tasksChrome(_ scope: TasksModel.Scope) -> PageChrome {
        let m = tasksModel(scope)
        let places = [
            SidebarContent.Item("Today", icon: "light_mode", count: scope == .today ? "\(m.count)" : "",
                                isOn: scope == .today) { [weak self] in self?.open(.today) },
            SidebarContent.Item("Upcoming", icon: "calendar_today", count: scope == .upcoming ? "\(m.count)" : "",
                                isOn: scope == .upcoming) { [weak self] in self?.open(.upcoming) },
            SidebarContent.Item("Inbox", icon: "inbox", count: inboxCount > 0 ? "\(inboxCount)" : "") { [weak self] in
                self?.open(.inbox)
            },
        ]
        var filters = [SidebarContent.Item("All courses", icon: "grid_view", isOn: m.course == nil) { m.course = nil }]
        for card in courses.cards {
            let n = m.tasks.filter { $0.source.courseID == card.id && !$0.done }.count
            filters.append(.init(card.course.name, dot: card.course.style.dot, count: n > 0 ? "\(n)" : "",
                                 isOn: m.course == card.id) { m.course = card.id })
        }
        let sidebar = SidebarContent(title: scope == .today ? "Today" : "Upcoming", actionTitle: "New task",
                                     actionIcon: "add_task", actionKey: "⌘⇧Space",
                                     sections: [.init("Places", places), .init("Courses", filters)],
                                     onAction: { [weak self] in self?.capture.open() })
        return PageChrome(sidebar: sidebar, inspector: nil)
    }
}
