import Foundation
import Testing
@testable import MarginCore

/// An actor that blocks its thread the way `fsync` or a big scan does.
private actor Blocker {
    private let dedicatedExecutor = DedicatedExecutor(label: "margin.test-blocker")
    nonisolated var unownedExecutor: UnownedSerialExecutor { dedicatedExecutor.asUnownedSerialExecutor() }
    private var running = 0
    private(set) var maxRunning = 0

    func block(seconds: TimeInterval) {
        running += 1
        maxRunning = max(maxRunning, running)
        Thread.sleep(forTimeInterval: seconds)
        running -= 1
    }
}

@Suite struct DedicatedExecutorTests {
    /// M7-02: blocking work in actors must not take threads from the cooperative pool, or an
    /// update that is ready waits for a free thread (seen as seconds of latency on a 4-core box).
    @Test func blockingActorsDoNotStarveTheCooperativePool() async throws {
        let blockers = (0..<24).map { _ in Blocker() }
        let jobs = blockers.map { b in Task { await b.block(seconds: 0.6) } }
        try await Task.sleep(nanoseconds: 100_000_000)          // every blocker is now inside its sleep
        let start = ContinuousClock.now
        await Task { }.value                                    // needs a pool thread
        let waited = ContinuousClock.now - start
        #expect(waited < .milliseconds(400), "a pool task waited \(waited) behind blocking actors")
        for j in jobs { await j.value }
    }

    @Test func jobsOfOneActorRunOneAtATimeInOrder() async {
        let blocker = Blocker()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { await blocker.block(seconds: 0.002) } }
        }
        #expect(await blocker.maxRunning == 1)
    }
}
