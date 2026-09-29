import Testing
@testable import MarginCore

@Suite struct ShortcutTests {
    @Test func parsesAndFormatsCanonically() throws {
        let s = try Shortcut(parsing: "cmd+shift+space")
        #expect(s == .quickCapture)
        #expect(s.description == "shift+cmd+space")
        #expect(try Shortcut(parsing: s.description) == s)
    }

    @Test func acceptsAliasesCaseAndSpaces() throws {
        #expect(try Shortcut(parsing: "Command + Option + K") == Shortcut(modifiers: [.cmd, .opt], key: "k"))
        #expect(try Shortcut(parsing: "control+alt+F5").description == "ctrl+opt+f5")
    }

    @Test func rejectsInvalid() {
        for bad in ["", "space", "cmd", "cmd+", "+space", "cmd+shift", "cmd+foo", "cmd+a+b", "cmd+f21", "cmd++a"] {
            #expect(throws: MarginError.self) { _ = try Shortcut(parsing: bad) }
        }
    }

    @Test func inMemoryServiceRegistersFiresUnregisters() throws {
        let service = InMemoryGlobalHotkeyService()
        let box = Counter()
        try service.register(.quickCapture) { box.bump() }
        #expect(service.fire(.quickCapture))
        #expect(box.value == 1)
        service.unregister(.quickCapture)
        #expect(!service.fire(.quickCapture))
        #expect(service.registered.isEmpty)
    }

    final class Counter: @unchecked Sendable {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}
