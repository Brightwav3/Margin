import AppKit
import SwiftUI
import Testing
import MarginCore
@testable import MarginUI

/// Icon names of the course icon picker and property types resolve to Lucide glyphs (names written
/// in the sources are checked by `scripts/lint-icons.py`).
@MainActor @Suite struct IconCoverageTests {
    @Test func courseAndPropertyIconsHaveGlyphs() {
        var names = CourseIconSuggester.studyIcons + CourseIconSuggester.subjects.flatMap(\.icons)
            + CourseIconSuggester.keywordIcons.map(\.icon)
        names += PropertyType.allCases.map { PropertyIcons.icon($0) }.filter { !$0.isEmpty }
        let missing = Set(names).filter { MarginIcons.lucideName(for: $0).flatMap { LucideIcons.shared.glyph($0) } == nil }
        #expect(missing.isEmpty, "missing: \(missing.sorted().joined(separator: ", "))")
    }
}

/// Names that come from data (sidebar items, menus, course icons) only show when drawn: every
/// gallery screen is rendered and no icon may be missing.
@MainActor @Suite(.serialized) struct IconRenderingTests {
    @Test func noScreenDrawsAMissingIcon() async throws {
        let size = MarginScreens.size
        for screen in MarginScreens.all {
            let host = NSHostingView(rootView: screen.make().frame(width: size.width, height: size.height))
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            window.orderOut(nil)
        }
        #expect(MarginIcons.missing.isEmpty, "missing: \(MarginIcons.missing.sorted().joined(separator: ", "))")
    }
}
