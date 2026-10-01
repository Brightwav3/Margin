import MarginCore
import SwiftUI

/// What the sidebar navigation page shows (`Sidebar.dc.html`, `panel`). Screens build one from
/// their services; `ShellPresets` holds the mockup's sample panels for the gallery.
public struct SidebarContent: Sendable {
    public struct Item: Identifiable, Sendable {
        public let id = UUID()
        public var title: String
        public var icon: String?
        public var dot: String?
        public var meta: String?
        public var count: String
        public var isOn: Bool
        /// The course the row stands for: right-click gives the course menu (2f).
        public var courseID: String?
        /// Runs on click; nil = the row is not interactive yet.
        public var action: (@MainActor @Sendable () -> Void)?

        public init(_ title: String, icon: String? = nil, dot: String? = nil, meta: String? = nil,
                    count: String = "", isOn: Bool = false, courseID: String? = nil,
                    action: (@MainActor @Sendable () -> Void)? = nil) {
            self.courseID = courseID
            self.title = title
            self.icon = icon
            self.dot = dot
            self.meta = meta
            self.count = count
            self.isOn = isOn
            self.action = action
        }
    }

    public struct Section: Identifiable, Sendable {
        public let id = UUID()
        public var label: String
        public var items: [Item]

        public init(_ label: String, _ items: [Item]) {
            self.label = label
            self.items = items
        }
    }

    public var title: String
    /// Course dot next to the title (course pages).
    public var dot: String?
    public var actionTitle: String
    public var actionIcon: String
    public var actionKey: String
    public var sections: [Section]
    /// Notes space (second page, switched by the dots at the bottom).
    public var notes: NotesSpace?
    /// Choices behind the title chevron (Courses ▾ → Cards / Timetable); empty = no menu.
    public var views: [Item]
    public var onAction: (@MainActor @Sendable () -> Void)?
    /// Course of a course page: right-click on the title gives the course menu.
    public var courseID: String?

    public init(title: String, dot: String? = nil, courseID: String? = nil, actionTitle: String, actionIcon: String = "add",
                actionKey: String = "", sections: [Section], notes: NotesSpace? = nil, views: [Item] = [],
                onAction: (@MainActor @Sendable () -> Void)? = nil) {
        self.title = title
        self.dot = dot
        self.courseID = courseID
        self.actionTitle = actionTitle
        self.actionIcon = actionIcon
        self.actionKey = actionKey
        self.sections = sections
        self.notes = notes
        self.views = views
        self.onAction = onAction
    }
}

/// The Notes page of the sidebar: back link, search, filters and grouped note list.
public struct NotesSpace: Sendable {
    public struct Note: Identifiable, Sendable {
        public let id = UUID()
        public var title: String
        public var snippet: String
        public var time: String
        public var isSelected: Bool
        /// The note behind the row: right-click gives the note menu (1a).
        public var summary: NoteSummary?
        public var action: (@MainActor @Sendable () -> Void)?

        public init(_ title: String, snippet: String, time: String, isSelected: Bool = false, summary: NoteSummary? = nil,
                    action: (@MainActor @Sendable () -> Void)? = nil) {
            self.summary = summary
            self.title = title
            self.snippet = snippet
            self.time = time
            self.isSelected = isSelected
            self.action = action
        }
    }

    public var courseName: String
    public var courseStyle: CourseStyle
    public var groups: [(title: String, notes: [Note])]
    public var onNew: (@MainActor @Sendable () -> Void)?

    public init(courseName: String, courseStyle: CourseStyle, groups: [(title: String, notes: [Note])],
                onNew: (@MainActor @Sendable () -> Void)? = nil) {
        self.courseName = courseName
        self.courseStyle = courseStyle
        self.groups = groups
        self.onNew = onNew
    }
}

/// One row in an inspector list (`r(title, meta, icon, count)`).
public struct InspectorRow: Identifiable, Sendable {
    public let id = UUID()
    public var title: String
    public var meta: String?
    public var icon: String?
    public var count: String
    public var indent: CGFloat
    public var isLink: Bool
    public var isBold: Bool
    public var action: (@MainActor @Sendable () -> Void)?

    public init(_ title: String, meta: String? = nil, icon: String? = nil, count: String = "",
                indent: CGFloat = 8, isLink: Bool = false, isBold: Bool = false,
                action: (@MainActor @Sendable () -> Void)? = nil) {
        self.action = action
        self.title = title
        self.meta = meta
        self.icon = icon
        self.count = count
        self.indent = indent
        self.isLink = isLink
        self.isBold = isBold
    }
}

/// Inspector data for the current page: which tab set and the rows / chat per tab.
public struct InspectorContent: Sendable {
    public enum Kind: Sendable { case note, course }

    public var kind: Kind
    public var rows: [InspectorTab: [InspectorRow]]
    public var titles: [InspectorTab: String]
    public var agentContext: (icon: String, text: String)
    public var chat: [(text: String, fromUser: Bool)]
    public var suggestions: [(icon: String, text: String)]
    public var placeholder: String

    public init(kind: Kind, rows: [InspectorTab: [InspectorRow]], titles: [InspectorTab: String] = [:],
                agentContext: (icon: String, text: String), chat: [(text: String, fromUser: Bool)],
                suggestions: [(icon: String, text: String)], placeholder: String) {
        self.kind = kind
        self.rows = rows
        self.titles = titles
        self.agentContext = agentContext
        self.chat = chat
        self.suggestions = suggestions
        self.placeholder = placeholder
    }

    /// The Agent tab shows only when it has something (the in-app agent is a later milestone).
    var tabs: [InspectorTab] {
        let all = kind == .course ? InspectorTab.course : InspectorTab.note
        return chat.isEmpty && suggestions.isEmpty ? all.filter { $0 != .agent } : all
    }
}

/// Rail entries: fixed places plus one circle per course.
public struct RailContent: Sendable {
    public enum Place: String, CaseIterable, Sendable {
        case home, inbox, today, upcoming

        var title: String {
            switch self {
            case .home: "Courses"
            case .inbox: "Inbox"
            case .today: "Today"
            case .upcoming: "Upcoming"
            }
        }

        var shortcut: String {
            switch self {
            case .home: ""
            case .today: "⌘1"
            case .upcoming: "⌘2"
            case .inbox: "⌘3"
            }
        }

        var icon: String {
            switch self {
            case .home: "home"
            case .inbox: "inbox"
            case .today: "light_mode"
            case .upcoming: "calendar_today"
            }
        }
    }

    public var active: String
    public var inboxHasItems: Bool
    public var courses: [(id: String, name: String, style: CourseStyle)]
    public var initials: String

    public init(active: String, inboxHasItems: Bool = true,
                courses: [(id: String, name: String, style: CourseStyle)], initials: String) {
        self.active = active
        self.inboxHasItems = inboxHasItems
        self.courses = courses
        self.initials = initials
    }
}
