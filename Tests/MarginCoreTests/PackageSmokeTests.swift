import Testing
@testable import MarginCore

@Test func coreModuleLoads() {
    #expect(!MarginCore.version.isEmpty)
}
