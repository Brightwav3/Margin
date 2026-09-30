import Foundation
import Observation
import SwiftUI

/// One open tab in the title bar.
public struct ShellTab: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    /// Course dot colour (`#RRGGBB`); grey for app pages (Courses, Inbox, Graph).
    public var dot: String
    /// What the tab shows (`course/bio`, `session/bio-tuesday-1000@2026-09-29`); nil = not addressable.
    public var route: String?

    public init(id: UUID = UUID(), title: String, dot: String = "#9A9DA6", route: String? = nil) {
        self.id = id
        self.title = title
        self.dot = dot
        self.route = route
    }
}

/// Left sidebar page: navigation for the current place, or the Notes space.
public enum SidebarPage: Int, Sendable { case navigation, notes }

/// Inspector tab. Course and note pages show different sets (`Inspector.dc.html`).
public enum InspectorTab: String, CaseIterable, Sendable {
    case agent, outline, backlinks, outgoing, properties, comingUp, courseInfo, files

    public static let note: [InspectorTab] = [.agent, .outline, .backlinks, .outgoing, .properties]
    public static let course: [InspectorTab] = [.agent, .comingUp, .courseInfo, .files]

    var icon: String {
        switch self {
        case .agent: "auto_awesome"
        case .outline: "toc"
        case .backlinks: "call_received"
        case .outgoing: "call_made"
        case .properties: "tune"
        case .comingUp: "event"
        case .courseInfo: "info"
        case .files: "folder"
        }
    }

    var label: String {
        switch self {
        case .agent: "Agent"
        case .outline: "Outline"
        case .backlinks: "Backlinks"
        case .outgoing: "Outgoing links"
        case .properties: "All properties"
        case .comingUp: "Coming up"
        case .courseInfo: "Course info"
        case .files: "Files"
        }
    }
}

/// Single source of truth for window state (`00-overview.md` §3): tabs and panels.
@MainActor @Observable
public final class AppModel {
    public var tabs: [ShellTab]
    public var activeTabID: UUID?
    public var sidebarCollapsed: Bool {
        didSet { defaults?.set(sidebarCollapsed, forKey: Self.collapsedKey) }
    }
    public var inspectorOpen: Bool
    public var sidebarPage: SidebarPage
    public var inspectorTab: InspectorTab
    /// User-chosen panel widths; nil = the default for the current content.
    public private(set) var sidebarWidth: CGFloat? {
        didSet { store(sidebarWidth, Self.sidebarWidthKey) }
    }
    public private(set) var inspectorWidth: CGFloat? {
        didSet { store(inspectorWidth, Self.inspectorWidthKey) }
    }

    public static let sidebarWidthRange: ClosedRange<CGFloat> = 180...440
    public static let inspectorWidthRange: ClosedRange<CGFloat> = 240...520

    private let defaults: UserDefaults?
    private static let collapsedKey = "shell.sidebarCollapsed"
    private static let sidebarWidthKey = "shell.sidebarWidth"
    private static let inspectorWidthKey = "shell.inspectorWidth"

    /// `defaults: nil` keeps the model in memory only (gallery, tests).
    public init(
        tabs: [ShellTab] = [], activeTabID: UUID? = nil, sidebarCollapsed: Bool? = nil,
        inspectorOpen: Bool = false, sidebarPage: SidebarPage = .navigation,
        inspectorTab: InspectorTab = .agent, defaults: UserDefaults? = nil
    ) {
        self.defaults = defaults
        self.tabs = tabs
        self.activeTabID = activeTabID ?? tabs.first?.id
        self.sidebarCollapsed = sidebarCollapsed ?? defaults?.bool(forKey: Self.collapsedKey) ?? false
        self.inspectorOpen = inspectorOpen
        self.sidebarPage = sidebarPage
        self.inspectorTab = inspectorTab
        self.sidebarWidth = defaults?.object(forKey: Self.sidebarWidthKey) as? CGFloat
        self.inspectorWidth = defaults?.object(forKey: Self.inspectorWidthKey) as? CGFloat
    }

    public var activeTab: ShellTab? { tabs.first { $0.id == activeTabID } }

    public func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    /// Opens a tab after the active one and activates it.
    @discardableResult
    public func open(_ tab: ShellTab) -> UUID {
        let index = tabs.firstIndex { $0.id == activeTabID }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: index)
        activeTabID = tab.id
        return tab.id
    }

    /// Activates the tab showing `tab.route` when one is open, else opens `tab`.
    @discardableResult
    public func show(_ tab: ShellTab) -> UUID {
        if let route = tab.route, let existing = tabs.first(where: { $0.route == route }) {
            activeTabID = existing.id
            return existing.id
        }
        return open(tab)
    }

    /// Closing the active tab activates its right neighbour, else the left one.
    public func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if activeTabID == id {
            activeTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    /// Moves a tab to a new index (drag to reorder).
    public func move(_ id: UUID, to newIndex: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: max(0, min(newIndex, tabs.count)))
    }

    public func toggleSidebar() { sidebarCollapsed.toggle() }

    /// Sets the sidebar width (clamped); nil restores the default.
    public func setSidebarWidth(_ width: CGFloat?) {
        sidebarWidth = width.map { min(max($0, Self.sidebarWidthRange.lowerBound), Self.sidebarWidthRange.upperBound) }
    }

    /// Sets the inspector width (clamped); nil restores the default.
    public func setInspectorWidth(_ width: CGFloat?) {
        inspectorWidth = width.map { min(max($0, Self.inspectorWidthRange.lowerBound), Self.inspectorWidthRange.upperBound) }
    }

    private func store(_ value: CGFloat?, _ key: String) {
        if let value { defaults?.set(Double(value), forKey: key) } else { defaults?.removeObject(forKey: key) }
    }
    public func toggleInspector() { inspectorOpen.toggle() }
}
