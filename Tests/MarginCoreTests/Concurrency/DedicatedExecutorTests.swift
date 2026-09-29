import Foundation
import Testing
@testable import MarginCore

/// An actor that runs on a dedicated executor and blocks its thread the way `fsync` or a big
/// scan does.
private actor Blocker {
    private let dedicatedExecutor = DedicatedExecutor(label: "margin.test-blocker")
    nonisolated var unownedExecutor: UnownedSerialExecutor { dedicatedExecutor.asUnownedSerialExecutor() }
    private var running = 0
    private(set) var maxRunning = 0

    func block(seconds: TimeInterval) -> Bool {
        running += 1
        maxRunning = max(maxRunning, running)
        Thread.sleep(forTimeInterval: seconds)
        running -= 1
        return dedicatedExecutor.isCurrentThread
    }
}

@Suite struct DedicatedExecutorTests {
    /// M7-02: blocking work in actors must run on the executor's own thread, not on a thread of
    /// the cooperative pool, or an update that is ready waits for a free pool thread (seen as
    /// seconds of latency on a 4-core box). Asserted by thread, not by timing, so the test does
    /// not depend on what other suites do to the pool at the same time.
    @Test func blockingWorkRunsOffTheCooperativePool() async {
        let blockers = (0..<12).map { _ in Blocker() }
        let onOwnThread = await withTaskGroup(of: Bool.self) { group in
            for b in blockers { group.addTask { await b.block(seconds: 0.05) } }
            var all: [Bool] = []
            for await r in group { all.append(r) }
            return all
        }
        #expect(onOwnThread.count == 12 && onOwnThread.allSatisfy { $0 })
    }

    @Test func jobsOfOneActorRunOneAtATime() async {
        let blocker = Blocker()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { _ = await blocker.block(seconds: 0.002) } }
        }
        #expect(await blocker.maxRunning == 1)
    }
}
