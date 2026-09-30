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

@Suite struct TabReorderTests {
    @Test func targetRoundsAndClamps() {
        #expect(TabReorder.target(from: 0, translation: 100, step: 190, count: 4) == 1)
        #expect(TabReorder.target(from: 0, translation: 90, step: 190, count: 4) == 0)
        #expect(TabReorder.target(from: 1, translation: -500, step: 190, count: 4) == 0)
        #expect(TabReorder.target(from: 1, translation: 5000, step: 190, count: 4) == 3)
    }

    @Test func neighboursSlideTowardsTheGap() {
        // Dragging tab 0 to 2: tabs 1 and 2 slide left, tab 3 stays.
        #expect((0...3).map { TabReorder.shift(index: $0, from: 0, to: 2, step: 10) } == [0, -10, -10, 0])
        // Dragging tab 3 to 1: tabs 1 and 2 slide right.
        #expect((0...3).map { TabReorder.shift(index: $0, from: 3, to: 1, step: 10) } == [0, 10, 10, 0])
    }
}

@Suite struct SwipeTrackerTests {
    typealias Input = SwipeTracker.Input

    @Test func oneStepPerTrackpadGesture() {
        var t = SwipeTracker()
        #expect(t.consume(Input(dx: -10, dy: 0, began: true)).step == nil)
        #expect(t.consume(Input(dx: -25, dy: 1)).step == 1)
        #expect(t.consume(Input(dx: -40, dy: 0)).step == nil)
        #expect(t.consume(Input(dx: -5, dy: 0, ended: true)).step == nil)
        // Next gesture the other way goes back.
        _ = t.consume(Input(dx: 20, dy: 0, began: true))
        #expect(t.consume(Input(dx: 20, dy: 0)).step == -1)
    }

    @Test func verticalScrollIsIgnoredAndPassesThrough() {
        var t = SwipeTracker()
        _ = t.consume(Input(dx: -5, dy: 30, began: true))
        let r = t.consume(Input(dx: -30, dy: 40))
        #expect(r.step == nil && !r.swallow)
    }

    @Test func respectsNonNaturalScrolling() {
        var t = SwipeTracker()
        _ = t.consume(Input(dx: 20, dy: 0, began: true, natural: false))
        #expect(t.consume(Input(dx: 20, dy: 0, natural: false)).step == 1)
    }

    @Test func mouseWheelStepsWithLock() {
        var t = SwipeTracker()
        #expect(t.consume(Input(dx: -3, dy: 0, hasPhase: false, time: 1)).step == 1)
        #expect(t.consume(Input(dx: -3, dy: 0, hasPhase: false, time: 1.2)).step == nil)
        #expect(t.consume(Input(dx: 3, dy: 0, hasPhase: false, time: 2)).step == -1)
    }
}

@MainActor @Suite struct PanelWidthTests {
    @Test func widthsClampAndReset() {
        let m = AppModel()
        m.setSidebarWidth(50)
        #expect(m.sidebarWidth == AppModel.sidebarWidthRange.lowerBound)
        m.setInspectorWidth(9999)
        #expect(m.inspectorWidth == AppModel.inspectorWidthRange.upperBound)
        m.setSidebarWidth(nil)
        #expect(m.sidebarWidth == nil)
    }

    @Test func widthsAreRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "margin.tests.\(UUID())"))
        AppModel(defaults: defaults).setSidebarWidth(300)
        let reopened = AppModel(defaults: defaults)
        #expect(reopened.sidebarWidth == 300)
        reopened.setSidebarWidth(nil)
        #expect(AppModel(defaults: defaults).sidebarWidth == nil)
    }
}
