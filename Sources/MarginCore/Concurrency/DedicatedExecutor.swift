import Foundation

/// A serial executor backed by its own dispatch queue, for actors and tasks that do blocking or
/// CPU-heavy synchronous work (file I/O with `fsync`, directory scans, hashing, index builds).
///
/// Swift's default executor is the cooperative thread pool, which has one thread per core. A job
/// that blocks a pool thread in `fsync` or crunches text for tens of milliseconds takes that
/// thread away from every other task in the process; when a few of them do it at once, unrelated
/// work, such as delivering a `TaskService.updates` event that is already computed, waits until a
/// thread is free again (M7-02: seconds on a 4-core machine that runs many vaults in parallel).
/// A serial dispatch queue gets a thread of its own (dispatch over-commits serial queues), so
/// its blocking work never competes with the pool, while jobs of one actor still run one at a
/// time, in order.
///
/// Use it as `unownedExecutor` of an actor, or as `Task(executorPreference:)`.
final class DedicatedExecutor: SerialExecutor, TaskExecutor, @unchecked Sendable {
    private let queue: DispatchQueue

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        queue.async { [self] in
            unowned.runSynchronously(isolatedTo: asUnownedSerialExecutor(), taskExecutor: asUnownedTaskExecutor())
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor { UnownedSerialExecutor(ordinary: self) }
    func asUnownedTaskExecutor() -> UnownedTaskExecutor { UnownedTaskExecutor(ordinary: self) }
}
