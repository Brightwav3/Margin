import MarginCore
import SwiftUI

/// Sidebar and inspector of a course page (`Sidebar.dc.html` course panel, `Inspector.dc.html` course).
extension Workspace {
    func courseModel(_ id: CourseID) -> CourseDetailModel {
        model("course/\(id)") { CourseDetailModel(env: env, course: id) }
    }

    func courseChrome(_ id: CourseID) -> PageChrome {
        let m = courseModel(id)
        let style = m.course?.style ?? courses.course(id: id)?.style
        let name = m.course?.name ?? courses.course(id: id)?.name ?? id
        let pages = CourseDetailModel.Page.allCases.map { page in
            let count: String = switch page {
            case .gallery: ""
            case .tasks: m.openTaskCount > 0 ? "\(m.openTaskCount)" : ""
            case .examPrep: "\(m.examPrep.filter { !$0.task.done }.count)"
            case .grades: m.grade?.letter ?? ""
            }
            return SidebarContent.Item(page.title, icon: page.icon, count: count == "0" ? "" : count,
                                       isOn: m.page == page) { m.page = page }
        }
        var views = pages
        views.append(.init("Graph", icon: "share") { [weak self] in self?.open(.graph) })

        let upcoming = m.cards.filter(\.isUpcoming).prefix(3).map { card in
            SidebarContent.Item("\(card.kind) · \(card.theme)", icon: "event_upcoming", meta: card.meta) { [weak self] in
                guard let self else { return }
                switch card.source {
                case .note(let n): self.open(note: n)
                case .upcoming(let o): self.open(session: o)
                }
            }
        }
        var sections = [SidebarContent.Section("Views", views)]
        if !upcoming.isEmpty { sections.append(.init("Next classes", Array(upcoming))) }

        let notes = notesSpace(for: m, name: name, style: style)
        let sidebar = SidebarContent(title: name, dot: style?.dot, courseID: m.courseID, actionTitle: "New lecture note",
                                     actionIcon: "edit_square", actionKey: "⌘N", sections: sections,
                                     notes: notes,
                                     onAction: { [weak self] in self?.newNote(in: m) })
        return PageChrome(sidebar: sidebar, inspector: courseInspector(m))
    }

    func newNote(in m: CourseDetailModel) {
        perform("New note") { [weak self] in
            if let note = try await m.createNote() { self?.open(note: note) }
        }
    }

    /// The Notes space of a course: notes grouped by This week / Last week / Earlier.
    func notesSpace(for m: CourseDetailModel, name: String, style: CourseStyle?) -> NotesSpace? {
        guard let style else { return nil }
        let today = env.clock.today
        let monday = today.startOfWeek
        let active = route
        var groups: [(String, [NotesSpace.Note])] = [("This week", []), ("Last week", []), ("Earlier", [])]
        let sorted = m.notes.filter { !$0.isPlaceholder }.sorted {
            ($0.date ?? $0.modified?.date ?? today) > ($1.date ?? $1.modified?.date ?? today)
        }
        for note in sorted {
            let date = note.date ?? note.modified?.date ?? today
            let index = date >= monday ? 0 : date >= monday.adding(days: -7) ? 1 : 2
            let item = NotesSpace.Note(note.title, snippet: note.snippet, time: CoursesFormat.weekday(date.weekday),
                                       isSelected: active == .note(note.id), summary: note) { [weak self] in self?.open(note: note) }
            groups[index].1.append(item)
        }
        return NotesSpace(courseName: name, courseStyle: style, groups: groups.filter { !$0.1.isEmpty },
                          onNew: { [weak self] in self?.newNote(in: m) })
    }

    func courseInspector(_ m: CourseDetailModel) -> InspectorContent {
        let coming = m.comingUp.map { item in
            InspectorRow(item.title, meta: item.meta, icon: item.icon, count: item.distance)
        }
        var info: [InspectorRow] = []
        if let c = m.course {
            if let p = c.professor { info.append(InspectorRow(p, meta: c.code, icon: "person")) }
            info.append(InspectorRow("Sessions", meta: m.sessionsLine, icon: "location_on"))
            if let credits = c.credits { info.append(InspectorRow("Credits", meta: "\(credits)", icon: "school")) }
            if let g = m.grade { info.append(InspectorRow("Grade so far", meta: "\(g.letter) · \(g.percent)%", icon: "bar_chart")) }
            for exam in c.exams {
                info.append(InspectorRow(exam.title, meta: "\(CourseDetailModel.day(exam.date)) · \(exam.weightPercent)%", icon: "quiz"))
            }
        }
        return InspectorContent(kind: .course, rows: [.comingUp: coming, .courseInfo: info, .files: []],
                                agentContext: (m.course?.style.icon ?? "school", m.course?.name ?? ""),
                                chat: [], suggestions: [], placeholder: "Ask about this course…")
    }
}
