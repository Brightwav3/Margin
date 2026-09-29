import Foundation

/// Keeps the progress of the index build and hands it to any number of streams. A new stream first
/// gets the current state (so a late subscriber sees the finished state), then the changes; every
/// stream ends after the complete element. Only whole-percent changes are reported.
final class IndexProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var state = IndexProgress(filesDone: 0, filesTotal: 0)
    private var reportedPercent = -1
    private var continuations: [UUID: AsyncStream<IndexProgress>.Continuation] = [:]
    private let observer: (@Sendable (IndexProgress) -> Void)?

    /// - Parameter observer: called for every reported element, in order (the loading screen callback).
    init(observer: (@Sendable (IndexProgress) -> Void)? = nil, complete total: Int? = nil) {
        self.observer = observer
        if let total {
            state = IndexProgress(filesDone: total, filesTotal: total, isComplete: true)
            reportedPercent = 100
        }
    }

    var current: IndexProgress { lock.lock(); defer { lock.unlock() }; return state }

    func subscribe() -> AsyncStream<IndexProgress> {
        let (stream, continuation) = AsyncStream<IndexProgress>.makeStream(bufferingPolicy: .unbounded)
        lock.lock()
        // Before the first report there is nothing to say yet; the first report is the first element.
        if reportedPercent >= 0 { continuation.yield(state) }
        if state.isComplete {
            continuation.finish()
        } else {
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in self?.remove(id) }
        }
        lock.unlock()
        return stream
    }

    /// `done` of `total` notes read. Reported only when the whole percent changed.
    func report(done: Int, total: Int) {
        emit(IndexProgress(filesDone: done, filesTotal: total), force: false)
    }

    /// The index is built (all notes of the last `report` are read).
    func finish() {
        let total = current.filesTotal
        emit(IndexProgress(filesDone: total, filesTotal: total, isComplete: true), force: true)
    }

    /// Ends every stream (shutdown), complete or not.
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

    private func emit(_ next: IndexProgress, force: Bool) {
        lock.lock()
        guard !state.isComplete, force || next.percent > reportedPercent else { lock.unlock(); return }
        reportedPercent = next.percent
        state = next
        let targets = Array(continuations.values)
        if next.isComplete { continuations = [:] }
        lock.unlock()
        // Outside the lock: finishing a stream runs its `onTermination`, which takes the lock.
        for c in targets { c.yield(next); if next.isComplete { c.finish() } }
        observer?(next)
    }
}
