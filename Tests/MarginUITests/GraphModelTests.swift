import CoreGraphics
import MarginCore
import Testing
@testable import MarginUI

@MainActor @Suite struct GraphModelTests {
    private func loaded() async -> GraphModel {
        let m = GraphModel(env: .fixture())
        await m.load()
        return m
    }

    @Test func loadsTheSemesterGraphWithPositions() async {
        let m = await loaded()
        #expect(m.graph.nodes.count == 23)
        #expect(m.positions.count == m.graph.nodes.count)
        #expect(m.graph.nodes.filter { $0.kind == .course }.count == 6)
    }

    @Test func hidingACourseRemovesItsNodes() async throws {
        let m = await loaded()
        m.hiddenCourses = ["bio"]
        try await Task.sleep(for: .milliseconds(100))
        #expect(!m.graph.nodes.contains { $0.courseID == "bio" })
    }

    @Test func hoverHighlightsNeighbours() async throws {
        let m = await loaded()
        let bio = try #require(m.graph.nodes.first { $0.kind == .course && $0.courseID == "bio" } ?? m.graph.nodes.first)
        m.hovered = bio.id
        #expect(m.hot.contains(bio.id) && m.hot.count == m.degree(bio.id) + 1)
    }

    @Test func hitTestingFindsTheNodeUnderThePointer() async throws {
        let m = await loaded()
        let size = CGSize(width: 1000, height: 800)
        let node = try #require(m.graph.nodes.first)
        let p = m.point(try #require(m.positions[node.id]), in: size)
        #expect(m.node(at: p, in: size)?.id == node.id)
        #expect(m.node(at: CGPoint(x: -500, y: -500), in: size) == nil)
    }

    @Test func zoomIsClamped() {
        let m = GraphModel(env: .fixture())
        for _ in 0..<40 { m.zoomIn() }
        #expect(m.zoom == 6)
        m.fit()
        #expect(m.zoom == 1 && m.offset == .zero)
    }

    @Test func labelsFollowZoom() async throws {
        let m = await loaded()
        let note = try #require(m.graph.nodes.first { $0.kind == .note })
        m.zoom = 0.3
        #expect(!m.showsLabel(note))
        m.zoom = 1
        #expect(m.showsLabel(note))
    }
}
