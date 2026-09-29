import Foundation
import Testing
@testable import MarginCore

/// `"\r\n"` is one `Character`, so character-based checks miss CRLF on macOS. Every "one line"
/// rule must still see it.
@Suite struct LineBreaksTests {
    @Test func everyLineBreakFormIsFound() {
        #expect("a\nb".containsLineBreak)
        #expect("a\r\nb".containsLineBreak)
        #expect("a\rb".containsLineBreak)
        #expect(!"one line".containsLineBreak)
        #expect(!"".containsLineBreak)
    }

    @Test func oneLineRulesRejectCRLF() {
        #expect(throws: PropertyValidationError.invalidKey("a\r\nb")) { try PropertyRegistry.validateKey("a\r\nb") }
        #expect(throws: MarginError.self) { _ = try CourseWriting.requireName("Bio\r\nlogy") }
    }
}
