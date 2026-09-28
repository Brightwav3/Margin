import Foundation

/// Fans one event source out to any number of `AsyncStream` subscribers.
///
/// `subscribe()` registers the subscriber before it returns, so an event sent right after the call
/// is delivered (a consumer that reads `service.updates` and then triggers a change never misses
/// it). A subscriber is dropped when its stream is cancelled or finished.
final class Broadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    func subscribe() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .unbounded)
        let id = UUID()
        lock.lock()
        continuations[id] = continuation
        lock.unlock()
        continuation.onTermination = { [weak self] _ in self?.remove(id) }
        return stream
    }

    func send(_ element: Element) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for c in targets { c.yield(element) }
    }

    /// Ends every stream (service shutdown).
    func finishAll() {
        lock.lock()
        let targets = Array(continuations.values)
        continuations = [:]
        lock.unlock()
        for c in targets { c.finish() }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}
