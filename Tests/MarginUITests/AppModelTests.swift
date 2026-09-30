import Foundation
import Testing
@testable import MarginUI

@MainActor @Suite struct AppModelTests {
    private func model() -> (AppModel, [ShellTab]) {
        let tabs = ["A", "B", "C", "D"].map { ShellTab(title: $0) }
        return (AppModel(tabs: tabs, activeTabID: tabs[1].id), tabs)
    }

    @Test func closingActiveTabActivatesRightNeighbour() {
        let (m, t) = model()
        m.close(t[1].id)
        #expect(m.activeTabID == t[2].id)
        m.close(t[3].id)
        m.select(t[2].id)
        m.close(t[2].id)
        #expect(m.activeTabID == t[0].id)
        m.close(t[0].id)
        #expect(m.activeTabID == nil && m.tabs.isEmpty)
    }

    @Test func closingInactiveTabKeepsSelection() {
        let (m, t) = model()
        m.close(t[3].id)
        #expect(m.activeTabID == t[1].id)
    }

    @Test func openInsertsAfterActiveAndActivates() {
        let (m, t) = model()
        let id = m.open(ShellTab(title: "New"))
        #expect(m.tabs.map(\.title) == ["A", "B", "New", "C", "D"])
        #expect(m.activeTabID == id)
        _ = t
    }

    @Test func moveReordersAndClamps() {
        let (m, t) = model()
        m.move(t[0].id, to: 2)
        #expect(m.tabs.map(\.title) == ["B", "C", "A", "D"])
        m.move(t[3].id, to: -5)
        #expect(m.tabs.map(\.title) == ["D", "B", "C", "A"])
        m.move(t[3].id, to: 99)
        #expect(m.tabs.map(\.title) == ["B", "C", "A", "D"])
    }

    @Test func sidebarCollapseIsRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "margin.tests.\(UUID())"))
        let first = AppModel(defaults: defaults)
        #expect(!first.sidebarCollapsed)
        first.toggleSidebar()
        #expect(AppModel(defaults: defaults).sidebarCollapsed)
    }
}
