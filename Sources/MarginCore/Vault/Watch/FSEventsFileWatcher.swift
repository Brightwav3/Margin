// Verified on macOS: `FSEventsFileWatcherTests` (create, modify, delete, renames, folder moves).
import Foundation

#if os(macOS)
import CoreServices

/// macOS watcher backed by an FSEventStream (file-level events, 0.1 s latency).
///
/// Same contract as `PollingFileWatcher`: vault-relative paths, markdown and `_files/` only,
/// dotfiles ignored, own writes swallowed via `OwnWriteRegistry`, and successive changes to one
/// path coalesced with `PollingFileWatcher.merge`. The baseline is scanned before `changes()`
/// returns. Directory-level events (rename/move of a folder) and dropped events trigger a full
/// rescan diffed against the known state, so nothing is lost.
///
/// A vault folder that is gone (unplugged drive, moved folder) is not "every file deleted": the last
/// snapshot is kept, nothing is reported, and when the folder is back one full rescan is diffed
/// against that snapshot (same rule as `PollingFileWatcher`, M12-03; the checks are shared).
public struct FSEventsFileWatcher: FileWatcher {
    public let root: URL
    public let latency: TimeInterval
    public let clock: any Clock
    public let ownWrites: OwnWriteRegistry?

    public init(root: URL, latency: TimeInterval = 0.1, clock: any Clock = SystemClock(),
                ownWrites: OwnWriteRegistry? = nil) {
        // FSEvents reports real paths (`/private/var/…`), so the root must be one too.
        self.root = PollingFileWatcher.canonicalRoot(root)
        self.latency = latency
        self.clock = clock
        self.ownWrites = ownWrites
    }

    private struct RawEvent: Sendable { let path: String; let flags: UInt32 }

    /// Bridges the C callback to Swift; retained for the lifetime of the stream.
    private final class Sink: @unchecked Sendable {
        let continuation: AsyncStream<[RawEvent]>.Continuation
        init(_ continuation: AsyncStream<[RawEvent]>.Continuation) { self.continuation = continuation }
    }

    public func changes() -> AsyncStream<[FileChange]> {
        let scanner = PollingFileWatcher(root: root, clock: clock, ownWrites: ownWrites)
        let baseline = scanner.scan(previous: [:])
        let (out, outCont) = AsyncStream<[FileChange]>.makeStream(bufferingPolicy: .unbounded)
        let (raw, rawCont) = AsyncStream<[RawEvent]>.makeStream(bufferingPolicy: .unbounded)

        let sink = Unmanaged.passRetained(Sink(rawCont))
        var context = FSEventStreamContext(version: 0, info: sink.toOpaque(), retain: nil, release: nil,
                                           copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let sink = Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] ?? []
            var events: [RawEvent] = []
            for i in 0..<min(count, paths.count) { events.append(RawEvent(path: paths[i], flags: eventFlags[i])) }
            sink.continuation.yield(events)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency, flags) else {
            sink.release()
            outCont.finish()
            return out
        }
        let queue = DispatchQueue(label: "margin.fsevents")
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)

        // The stream ref is not Sendable; it is only touched again from `onTermination`.
        nonisolated(unsafe) let streamRef = stream
        let rootPath = root.path
        // Events stop when the folder goes away and may not come when it returns (a remounted volume
        // is a new directory): a light check turns each change of availability into a rescan request.
        let watchedRoot = self.root
        let availability = Task {
            var wasAvailable = PollingFileWatcher.rootIsAvailable(watchedRoot)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let now = PollingFileWatcher.rootIsAvailable(watchedRoot)
                if now != wasAvailable {
                    wasAvailable = now
                    rawCont.yield([RawEvent(path: rootPath, flags: UInt32(kFSEventStreamEventFlagRootChanged))])
                }
            }
        }
        let task = Task { [self] in
            var known = baseline
            // Set while the folder is gone; the first batch after it is back is a full rescan.
            var rootWasMissing = !PollingFileWatcher.rootIsAvailable(watchedRoot)
            for await events in raw {
                guard PollingFileWatcher.rootIsAvailable(watchedRoot) else {
                    rootWasMissing = true   // keep `known`: nothing was deleted, the folder is away
                    continue
                }
                var found: [FileChange] = []
                var needsRescan = rootWasMissing
                rootWasMissing = false
                var touched = Set<String>()
                for e in events {
                    let f = Int(e.flags)
                    if f & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
                            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0
                        || f & kFSEventStreamEventFlagItemIsDir != 0 {
                        needsRescan = true
                        continue
                    }
                    guard let rel = Self.relativePath(e.path, root: rootPath),
                          PollingFileWatcher.isWatched(components: rel.split(separator: "/").map(String.init))
                    else { continue }
                    touched.insert(rel)
                }
                if needsRescan {
                    let next = scanner.scan(previous: known)
                    found += await diff(old: known, new: next, paths: Set(known.keys).union(next.keys))
                    known = next
                } else if !touched.isEmpty {
                    guard let next = PollingFileWatcher.refresh(known, touched: touched, root: watchedRoot) else {
                        rootWasMissing = true   // the folder went away while this batch was handled
                        continue
                    }
                    found += await diff(old: known, new: next, paths: touched)
                    known = next
                }
                var pending: [String: FileChange.Kind] = [:]
                for c in found { PollingFileWatcher.merge(&pending, c) }
                if !pending.isEmpty {
                    outCont.yield(pending.map { FileChange(path: $0.key, kind: $0.value) }.sorted { $0.path < $1.path })
                }
            }
            outCont.finish()
        }
        outCont.onTermination = { _ in
            // The callback runs on `queue` and uses `sink`. Tearing down on the same serial queue
            // waits for a callback in progress, and none runs after the invalidation, so the sink
            // is released only when nothing can touch it (releasing it from here crashed the app).
            queue.async {
                FSEventStreamStop(streamRef)
                FSEventStreamInvalidate(streamRef)
                FSEventStreamRelease(streamRef)
                rawCont.finish()
                sink.release()
            }
            task.cancel()
            availability.cancel()
        }
        return out
    }

    /// Compares `paths` between snapshots; content-identical entries are not changes.
    private func diff(old: [String: PollingFileWatcher.Entry], new: [String: PollingFileWatcher.Entry],
                      paths: Set<String>) async -> [FileChange] {
        var out: [FileChange] = []
        for path in paths.sorted() {
            switch (old[path], new[path]) {
            case let (o?, e?):
                // Untouched only when content, time and size are all the same. A rewrite back to the
                // content the watcher last saw is still a change: in between the app may have written
                // (and been undone from outside) or read a passing state into the index, and FSEvents
                // coalesces all of it into one batch. Same rule as `PollingFileWatcher`.
                let sameContent = o.hash != nil ? o.hash == e.hash : true
                if sameContent, o.mtime == e.mtime, o.size == e.size { continue }
                if let ownWrites, let h = e.hash, await ownWrites.consumeLatest(path: path, hash: h) { continue }
                out.append(FileChange(path: path, kind: .modified))
            case let (nil, e?):
                if let ownWrites, let h = e.hash, await ownWrites.consumeLatest(path: path, hash: h) { continue }
                out.append(FileChange(path: path, kind: .created))
            case (_?, nil):
                if let ownWrites, await ownWrites.consumeLatest(path: path, hash: OwnWriteRegistry.deletedHash) { continue }
                out.append(FileChange(path: path, kind: .deleted))
            case (nil, nil):
                continue
            }
        }
        return out
    }

    static func relativePath(_ path: String, root: String) -> String? {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let rel = String(path.dropFirst(prefix.count))
        return rel.isEmpty ? nil : rel
    }
}
#endif
