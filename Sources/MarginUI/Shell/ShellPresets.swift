import MarginCore
import SwiftUI

/// Sample shell content copied from `Sidebar.dc.html` and `Inspector.dc.html` for the gallery.
/// Real screens build `SidebarContent` / `InspectorContent` from services.
enum ShellPresets {
    typealias Item = SidebarContent.Item
    typealias Section = SidebarContent.Section

    static var courses: [Course] { Fixtures.week5.courses }

    static func style(_ id: String) -> CourseStyle {
        courses.first { $0.id == id }?.style ?? CoursePalette.style(icon: "", color: "")
    }

    static func rail(active: String) -> RailContent {
        RailContent(active: active,
                    courses: courses.map { ($0.id, $0.name, $0.style) },
                    initials: "AK")
    }

    static func tabs(active: String) -> (tabs: [ShellTab], active: UUID) {
        let titles: [(String, String)] = [
            ("Cell membrane", "#6FBF7A"), (active, active == "Cell Biology" ? "#6FBF7A" : "#9A9DA6"),
            ("Problem set 4", "#6E97EC"), ("The 1848 revolutions", "#E8B85C"),
        ]
        let tabs = titles.map { ShellTab(title: $0.0, dot: $0.1) }
        return (tabs, tabs[1].id)
    }

    static let grid = SidebarContent(
        title: "Courses", actionTitle: "New course",
        sections: [
            Section("Groups", [
                Item("All courses", icon: "grid_view", count: "6", isOn: true),
                Item("Sciences", icon: "science", count: "3"),
                Item("Maths", icon: "change_history", count: "1"),
                Item("Humanities", icon: "account_balance", count: "2"),
            ]),
            Section("Semesters", [
                Item("Fall 2026", icon: "school", meta: "Current · week 5 of 14"),
                Item("Spring 2026", icon: "inventory_2", meta: "Archived · GPA 3.6"),
                Item("Fall 2025", icon: "inventory_2", meta: "Archived · GPA 3.5"),
            ]),
        ]
    )

    static var course: SidebarContent {
        let bio = style("bio")
        return SidebarContent(
            title: "Cell Biology", dot: bio.dot, actionTitle: "New lecture note", actionIcon: "edit_square",
            actionKey: "⌘N",
            sections: [
                Section("Views", [
                    Item("Gallery", icon: "grid_view", isOn: true),
                    Item("Tasks", icon: "check_box", count: "5"),
                    Item("Grades", icon: "bar_chart", count: "A−"),
                    Item("Graph", icon: "share"),
                ]),
                Section("Weeks", [
                    Item("Week 5", dot: bio.dot, meta: "Lecture 9 tomorrow", count: "1"),
                    Item("Week 4", dot: "#C4C7CF", meta: "Cell membrane, Organelles", count: "3"),
                    Item("Week 3", dot: "#C4C7CF", count: "3"),
                    Item("Week 2", dot: "#C4C7CF", count: "2"),
                ]),
                Section("Pinned", [
                    Item("Midterm formula sheet", icon: "push_pin"),
                    Item("Glossary", icon: "push_pin"),
                ]),
            ],
            notes: NotesSpace(courseName: "Cell Biology", courseStyle: bio, groups: [
                ("This week", [
                    .init("Lecture 8 — Cell membrane", snippet: "Phospholipid bilayer and the fluid mosaic model.",
                          time: "Thu", isSelected: true),
                    .init("Membrane transport summary", snippet: "Passive vs active transport, with examples.", time: "Wed"),
                ]),
                ("Last week", [
                    .init("Lecture 7 — Organelles", snippet: "Structure and function of each organelle.", time: "Tue"),
                    .init("Lecture 6 — Prokaryotes", snippet: "Key differences from eukaryotic cells.", time: "Thu"),
                    .init("Glossary", snippet: "Terms to know for the midterm.", time: "Mon"),
                ]),
            ])
        )
    }

    static let noteInspector = InspectorContent(
        kind: .note,
        rows: [
            .outline: [
                InspectorRow("Lecture 8 — Cell membrane", isBold: true),
                InspectorRow("Fluid mosaic model", indent: 22),
                InspectorRow("To do", indent: 22),
                InspectorRow("Related", indent: 22),
            ],
            .backlinks: [
                InspectorRow("Membrane transport summary", meta: "…builds on [[Lecture 8 — Cell membrane]] for the bilayer…",
                             icon: "description", isLink: true),
                InspectorRow("Midterm formula sheet", meta: "…see [[Lecture 8]] for cholesterol…",
                             icon: "description", isLink: true),
                InspectorRow("Lipids", meta: "Organic Chemistry · linked in Related", icon: "description", isLink: true),
            ],
            .outgoing: [
                InspectorRow("Membrane transport", meta: "Cell Biology", icon: "description", isLink: true),
                InspectorRow("Lipids", meta: "Organic Chemistry", icon: "description", isLink: true),
                InspectorRow("Osmosis", meta: "Not created yet", icon: "add_circle"),
            ],
            .properties: [
                InspectorRow("date", icon: "calendar_today", count: "142"),
                InspectorRow("class", icon: "notes", count: "142"),
                InspectorRow("tags", icon: "sell", count: "98"),
                InspectorRow("type", icon: "category", count: "142"),
                InspectorRow("due", icon: "event", count: "36"),
                InspectorRow("weight", icon: "percent", count: "21"),
            ],
        ],
        titles: [.backlinks: "Backlinks · 3", .outgoing: "Outgoing links · 3"],
        agentContext: ("description", "Lecture 8 — Cell membrane"),
        chat: [("Quiz me on this note", true),
               ("Which molecule keeps the membrane fluid at low temperatures, and how does it do it?", false)],
        suggestions: [("summarize", "Summarize this note"), ("add_link", "Suggest links to other notes"),
                      ("style", "Turn into flashcards")],
        placeholder: "Ask about this note…"
    )

    static let courseInspector = InspectorContent(
        kind: .course,
        rows: [
            .comingUp: [
                InspectorRow("Midterm", meta: "Thu 1 Oct · lectures 1–8", icon: "quiz", count: "3d"),
                InspectorRow("Problem set 3", meta: "Fri 2 Oct · 10%", icon: "assignment", count: "4d"),
                InspectorRow("Lecture 9 — Membrane transport", meta: "Tue 29 Sep · 10:00 · Sci 204",
                             icon: "event_upcoming", count: "1d"),
            ],
            .courseInfo: [
                InspectorRow("Dr. Okafor", meta: "okafor@uni.edu", icon: "person"),
                InspectorRow("Office hours", meta: "Tue 14:00 · Sci 310", icon: "schedule"),
                InspectorRow("Sessions", meta: "Tue, Thu 10:00 · Sci 204", icon: "location_on"),
                InspectorRow("Grade so far", meta: "A− · 91%", icon: "bar_chart"),
            ],
            .files: [
                InspectorRow("Syllabus.pdf", icon: "picture_as_pdf"),
                InspectorRow("Lab manual.pdf", icon: "picture_as_pdf"),
                InspectorRow("Past papers", icon: "folder", count: "4"),
            ],
        ],
        agentContext: ("eco", "Cell Biology · 16 notes"),
        chat: [("What should I focus on before the midterm?", true),
               ("Lectures 6–8 carry most of the marks. You have 2 open tasks in Lecture 8, and the membrane diagram came up in both past papers.", false)],
        suggestions: [("quiz", "Make a study plan until Thursday"), ("style", "Flashcards from lectures 1–8")],
        placeholder: "Ask about this course…"
    )
}

/// Gallery wrapper: owns an in-memory `AppModel` so each screen starts from its configuration.
struct ShellPreviewScreen: View {
    @State private var model: AppModel
    let rail: RailContent
    let sidebar: SidebarContent
    let inspector: InspectorContent?

    init(activeTab: String, railActive: String, sidebar: SidebarContent, inspector: InspectorContent?,
         collapsed: Bool = false, inspectorOpen: Bool = false, page: SidebarPage = .navigation,
         inspectorTab: InspectorTab = .agent) {
        let tabs = ShellPresets.tabs(active: activeTab)
        _model = State(initialValue: AppModel(
            tabs: tabs.tabs, activeTabID: tabs.active, sidebarCollapsed: collapsed,
            inspectorOpen: inspectorOpen, sidebarPage: page, inspectorTab: inspectorTab
        ))
        self.rail = ShellPresets.rail(active: railActive)
        self.sidebar = sidebar
        self.inspector = inspector
    }

    var body: some View {
        MarginShell(model: model, rail: rail, sidebar: sidebar, inspector: inspector) {
            Color.clear
        }
    }
}
