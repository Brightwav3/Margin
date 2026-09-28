import Foundation

/// A first-in-first-out mutual exclusion lock that can be held across `await` (unlike an actor,
/// which lets other calls in at every suspension point). Used to run whole write transactions one
/// at a time.
final class AsyncMutex: @unchecked Sendable {
    private let state = NSLock()
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.lock()
            if locked {
                waiters.append(continuation)
                state.unlock()
            } else {
                locked = true
                state.unlock()
                continuation.resume()
            }
        }
    }

    func unlock() {
        state.lock()
        if waiters.isEmpty {
            locked = false
            state.unlock()
        } else {
            let next = waiters.removeFirst()
            state.unlock()
            next.resume()   // ownership passes directly to the next waiter
        }
    }

    /// Runs `body` while holding the lock, on the caller's actor.
    func withLock<T>(isolation: isolated (any Swift.Actor)? = #isolation, _ body: () async throws -> T) async rethrows -> T {
        await lock()
        defer { unlock() }
        return try await body()
    }
}
