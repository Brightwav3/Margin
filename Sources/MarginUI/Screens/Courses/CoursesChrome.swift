import MarginCore
import SwiftUI

/// Sidebar of the courses home (`Sidebar.dc.html`, views `grid` and `timetable`).
extension Workspace {
    var coursesSidebar: SidebarContent {
        let model = self.courses
        let views = [
            SidebarContent.Item("Cards", isOn: model.mode == .grid) { model.mode = .grid },
            SidebarContent.Item("Timetable", isOn: model.mode == .timetable) { model.mode = .timetable },
        ]
        switch model.mode {
        case .grid:
            return SidebarContent(title: "Courses", actionTitle: "New course",
                                  sections: [groupsSection, semestersSection], views: views,
                                  onAction: { [weak self] in self?.dialog = .newCourse })
        case .timetable:
            return SidebarContent(title: "Timetable", actionTitle: "Add session",
                                  sections: [weeksSection, showSection], views: views)
        }
    }

    var groupsSection: SidebarContent.Section {
        let model = self.courses
        var items = [SidebarContent.Item("All courses", icon: "grid_view", count: "\(model.cards.count)",
                                         isOn: model.faculty == nil) { model.faculty = nil }]
        for faculty in model.faculties {
            let courses = model.cards.filter { $0.course.faculty == faculty }
            items.append(.init(faculty, icon: courses.first?.course.style.icon ?? "school",
                               count: "\(courses.count)", isOn: model.faculty == faculty) { model.faculty = faculty })
        }
        return .init("Groups", items)
    }

    var semestersSection: SidebarContent.Section {
        let current = courses.semester?.id
        let items = courses.semesters.reversed().map { semester in
            let meta: String
            if semester.id == current, let week = courses.currentWeek {
                meta = "Current · week \(week) of \(semester.weekCount)"
            } else {
                meta = semester.isArchived ? "Archived" : (semester.id == current ? "Current" : "")
            }
            return SidebarContent.Item(semester.name, icon: semester.isArchived ? "inventory_2" : "school",
                                       meta: meta.isEmpty ? nil : meta, isOn: false) { [weak self] in
                if semester.isArchived { self?.open(.archive) }
            }
        }
        return .init("Semesters", items)
    }

    var weeksSection: SidebarContent.Section {
        let model = self.courses
        guard let semester = model.semester else { return .init("Weeks", []) }
        let anchor = courses.currentWeek ?? model.week
        let weeks = (anchor - 1...anchor + 2).filter { $0 >= 1 && $0 <= semester.weekCount }
        let items = weeks.map { week in
            let isBreak = semester.breakWeeks.contains(week)
            var meta = isBreak ? "Reading week" : model.range(ofWeek: week)
            if week == courses.currentWeek { meta += " · now" }
            return SidebarContent.Item("Week \(week)", icon: "date_range", meta: meta, isOn: week == model.week) {
                Task { await model.showWeek(week) }
            }
        }
        return .init("Weeks", items)
    }

    var showSection: SidebarContent.Section {
        let model = self.courses
        let items = CoursesOverviewModel.KindGroup.allCases.map { group in
            let shown = !model.hiddenKinds.contains(group)
            return SidebarContent.Item(group.title, icon: shown ? "check_box" : "check_box_outline_blank",
                                       count: "\(model.count(of: group))") { model.toggle(group) }
        }
        return .init("Show", items)
    }
}
