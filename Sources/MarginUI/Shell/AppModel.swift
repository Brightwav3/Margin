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
        self.lastTabID = activeTabID ?? tabs.first?.id
        self.sidebarCollapsed = sidebarCollapsed ?? defaults?.bool(forKey: Self.collapsedKey) ?? false
        self.inspectorOpen = inspectorOpen
        self.sidebarPage = sidebarPage
        self.inspectorTab = inspectorTab
        self.sidebarWidth = defaults?.object(forKey: Self.sidebarWidthKey) as? CGFloat
        self.inspectorWidth = defaults?.object(forKey: Self.inspectorWidthKey) as? CGFloat
    }

    public var activeTab: ShellTab? { tabs.first { $0.id == activeTabID } }

    // MARK: Places and tabs
    //
    // Only notes live in tabs. Places (courses, a course, Today, Inbox, graph…) show in the content
    // area with no tab active; `place` is the route key of the place shown then.

    /// Route key of the page shown while no tab is active.
    public var place: String = "courses"
    /// The tab a note opens in when no tab is active („everything lives in one tab“).
    public private(set) var lastTabID: UUID?

    public enum Location: Hashable, Sendable {
        case tab(UUID)
        case place(String)
    }

    public var location: Location { activeTabID.map(Location.tab) ?? .place(place) }

    /// Shows a place; the tabs stay, none is active.
    public func showPlace(_ key: String) {
        guard location != .place(key) else { return }
        remember(location)
        activeTabID = nil
        place = key
    }

    public func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }), activeTabID != id else { return }
        remember(location)
        activeTabID = id
        lastTabID = id
    }

    /// Opens a tab after the active (or last used) one and activates it.
    @discardableResult
    public func open(_ tab: ShellTab) -> UUID {
        let anchor = activeTabID ?? lastTabID
        let index = tabs.firstIndex { $0.id == anchor }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: index)
        remember(location)
        activeTabID = tab.id
        lastTabID = tab.id
        return tab.id
    }

    /// Shows `tab.route`: its open tab, else the active or last used tab with new content, else a
    /// new tab. `newTab` always opens one (⌘-click, Open in new tab).
    @discardableResult
    public func show(_ tab: ShellTab, newTab: Bool = false) -> UUID {
        if let route = tab.route, let existing = tabs.first(where: { $0.route == route }) {
            select(existing.id)
            return existing.id
        }
        if !newTab, let reuse = activeTabID ?? lastTabID, let i = tabs.firstIndex(where: { $0.id == reuse }) {
            remember(location)
            tabs[i].title = tab.title
            tabs[i].dot = tab.dot
            tabs[i].route = tab.route
            activeTabID = reuse
            lastTabID = reuse
            return reuse
        }
        return open(tab)
    }

    /// Closing the active tab activates its right neighbour, else the left one, else the place.
    public func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if lastTabID == id { lastTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id }
        if activeTabID == id {
            activeTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    // MARK: Back / forward (title bar arrows, Go › Back ⌥⌘←)

    private var backStack: [Location] = []
    private var forwardStack: [Location] = []

    private func remember(_ from: Location) {
        if backStack.last != from { backStack.append(from) }
        if backStack.count > 100 { backStack.removeFirst() }
        forwardStack.removeAll()
    }

    private func isValid(_ l: Location) -> Bool {
        if case .tab(let id) = l { return tabs.contains { $0.id == id } }
        return true
    }

    public var canGoBack: Bool { backStack.contains { isValid($0) && $0 != location } }
    public var canGoForward: Bool { forwardStack.contains { isValid($0) && $0 != location } }

    private func go(to l: Location) {
        switch l {
        case .tab(let id): activeTabID = id; lastTabID = id
        case .place(let key): activeTabID = nil; place = key
        }
    }

    public func goBack() {
        while let l = backStack.popLast() {
            guard isValid(l), l != location else { continue }
            forwardStack.append(location)
            go(to: l)
            return
        }
    }

    public func goForward() {
        while let l = forwardStack.popLast() {
            guard isValid(l), l != location else { continue }
            backStack.append(location)
            go(to: l)
            return
        }
    }

    /// Next / previous tab (Window › Next tab ⌃⇥).
    public func cycleTab(_ step: Int) {
        guard !tabs.isEmpty else { return }
        let i = tabs.firstIndex(where: { $0.id == (activeTabID ?? lastTabID) }) ?? -1
        select(tabs[((i + step) % tabs.count + tabs.count) % tabs.count].id)
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
