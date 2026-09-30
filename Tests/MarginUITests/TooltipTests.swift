import Testing
@testable import MarginUI

@Suite struct TooltipTests {
    @Test func trailingShortcutIsSplitOff() {
        #expect(TooltipText.split("Toggle sidebar (⌥⌘S)", nil) == ("Toggle sidebar", "⌥⌘S"))
        #expect(TooltipText.split("New tab (⌘T)", nil) == ("New tab", "⌘T"))
        #expect(TooltipText.split("Search", "⌘K") == ("Search", "⌘K"))
        // Parentheses that are not a shortcut stay in the label.
        #expect(TooltipText.split("Lecture 8 (draft)", nil) == ("Lecture 8 (draft)", nil))
    }
}
