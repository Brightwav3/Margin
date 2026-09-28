import Foundation

#if os(macOS)
/// macOS watcher. Currently delegates to `PollingFileWatcher`.
// TODO(M5-07): macOS-only FSEvents implementation, verify on Mac (was not compiled on Linux)
public struct FSEventsFileWatcher: FileWatcher {
    private let fallback: PollingFileWatcher

    public init(root: URL, clock: any Clock = SystemClock(), ownWrites: OwnWriteRegistry? = nil) {
        self.fallback = PollingFileWatcher(root: root, clock: clock, ownWrites: ownWrites)
    }

    public func changes() -> AsyncStream<[FileChange]> { fallback.changes() }
}
#endif
