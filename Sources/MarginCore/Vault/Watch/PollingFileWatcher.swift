import Foundation

/// Portable watcher (Linux and macOS): periodically scans the vault, comparing mtime and size.
/// Files modified within `recentWindow` seconds of the scan also get a content hash compared on
/// later scans, which catches same-size edits inside one mtime tick. Changes are debounced: a
/// batch is emitted after one scan that found nothing new, and successive edits are coalesced.
public struct PollingFileWatcher: FileWatcher {
    public let root: URL
    public let interval: TimeInterval
    public let clock: any Clock
    public let ownWrites: OwnWriteRegistry?
    private let hashProvider: @Sendable (URL) -> String?
    private let recentWindow: TimeInterval = 2

    /// - Parameters:
    ///   - interval: seconds between scans (default 0.3).
    ///   - ownWrites: registry consulted to swallow the app's own writes.
    ///   - hashProvider: computes a file's content hash (must match what the store registers).
    public init(
        root: URL,
        interval: TimeInterval = 0.3,
        clock: any Clock = SystemClock(),
        ownWrites: OwnWriteRegistry? = nil,
        hashProvider: @escaping @Sendable (URL) -> String? = { PollingFileWatcher.sha256Hex(ofFileAt: $0) }
    ) {
        self.root = Self.canonicalRoot(root)
        self.interval = interval
        self.clock = clock
        self.ownWrites = ownWrites
        self.hashProvider = hashProvider
    }

    /// Lowercase hex SHA-256 (`ContentHash.hex`) of a file's bytes, or `nil` when unreadable.
    public static func sha256Hex(ofFileAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ContentHash(of: data).hex
    }

    struct Entry: Equatable {
        var mtime: Date
        var size: Int
        var hash: String?
    }

    public func changes() -> AsyncStream<[FileChange]> {
        let baseline = scan(previous: [:])
        let (stream, continuation) = AsyncStream<[FileChange]>.makeStream(bufferingPolicy: .unbounded)
        // Scans read the disk and hash files synchronously: a thread of their own, not the pool.
        let executor = DedicatedExecutor(label: "margin.file-watcher")
        let task = Task(executorPreference: executor) { [self] in
            var snapshot = baseline
            var pending: [String: FileChange.Kind] = [:]
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 0.001) * 1_000_000_000))
                if Task.isCancelled { break }
                let next = scan(previous: snapshot)
                let found = await diff(old: snapshot, new: next)
                snapshot = next
                if found.isEmpty {
                    if !pending.isEmpty {
                        let batch = pending.map { FileChange(path: $0.key, kind: $0.value) }
                            .sorted { $0.path < $1.path }
                        pending = [:]
                        continuation.yield(batch)
                    }
                } else {
                    for c in found { Self.merge(&pending, c) }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: - Diff and coalescing

    private func diff(old: [String: Entry], new: [String: Entry]) async -> [FileChange] {
        var out: [FileChange] = []
        for (path, e) in new {
            let kind: FileChange.Kind
            if let o = old[path] {
                let hashSame = (o.hash == nil || e.hash == nil) || o.hash == e.hash
                if o.mtime == e.mtime, o.size == e.size, hashSame { continue }
                kind = .modified
            } else {
                kind = .created
            }
            if let ownWrites, let h = e.hash ?? hashProvider(root.appendingPathComponent(path)),
               await ownWrites.consume(path: path, hash: h) {
                continue
            }
            out.append(FileChange(path: path, kind: kind))
        }
        for path in old.keys where new[path] == nil {
            if let ownWrites, await ownWrites.consume(path: path, hash: OwnWriteRegistry.deletedHash) { continue }
            out.append(FileChange(path: path, kind: .deleted))
        }
        return out
    }

    static func merge(_ pending: inout [String: FileChange.Kind], _ change: FileChange) {
        guard let existing = pending[change.path] else { pending[change.path] = change.kind; return }
        switch (existing, change.kind) {
        case (.created, .modified): pending[change.path] = .created
        case (.created, .deleted): pending[change.path] = nil
        case (.deleted, .created): pending[change.path] = .modified
        case (.modified, .deleted): pending[change.path] = .deleted
        default: pending[change.path] = change.kind
        }
    }

    // MARK: - Scanning

    func scan(previous: [String: Entry]) -> [String: Entry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        // A vault folder that is gone (unplugged drive, moved folder) is not "every file deleted":
        // report nothing and compare again when it is back.
        guard Self.rootIsAvailable(root) else { return previous }
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                     options: [.skipsHiddenFiles]) else { return [:] }
        let rootCount = root.pathComponents.count
        let now = clock.now
        var result: [String: Entry] = [:]
        for case let url as URL in en {
            let comps = Array(url.pathComponents.dropFirst(rootCount))
            if comps.contains(where: { $0.hasPrefix(".") }) {
                en.skipDescendants()
                continue
            }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isDirectory != true else { continue }
            guard Self.isWatched(components: comps) else { continue }
            let path = comps.joined(separator: "/")
            let mtime = v.contentModificationDate ?? Date(timeIntervalSince1970: 0)
            let size = v.fileSize ?? 0
            var entry = Entry(mtime: mtime, size: size, hash: nil)
            let isRecent = now.timeIntervalSince(mtime) < recentWindow
            let changed = previous[path].map { $0.mtime != mtime || $0.size != size } ?? true
            if changed || isRecent {
                // New/changed files are hashed (own-write matching); recent ones are re-hashed
                // so same-size edits within one mtime tick are still noticed. Time and size are
                // read again with the hash: the enumerator's values may predate the bytes.
                guard let fresh = Self.consistentEntry(at: url, hashProvider: hashProvider) else { continue }
                entry = fresh
            } else {
                entry.hash = previous[path]?.hash
            }
            result[path] = entry
        }
        return result
    }

    /// The folder's real path (`realpath`), so it has the same form as the URLs a directory
    /// enumerator and FSEvents report. `resolvingSymlinksInPath` is not enough: on macOS it maps
    /// `/private/var/…` back to `/var/…`, while the enumerator returns `/private/var/…`, which shifts
    /// every vault-relative path by one component. Falls back to the standardized URL while the
    /// folder does not exist. Shared with `FSEventsFileWatcher`.
    static func canonicalRoot(_ root: URL) -> URL {
        guard let resolved = realpath(root.path, nil) else { return root.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// Whether the vault folder itself exists. While it does not (unplugged drive, unmounted share,
    /// moved folder) no watcher may treat the files as deleted: it keeps its last snapshot and compares
    /// again when the folder is back (M12-03). Shared with `FSEventsFileWatcher`.
    static func rootIsAvailable(_ root: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &isFolder) && isFolder.boolValue
    }

    /// `known` with the entries of the vault-relative paths `touched` read again from disk (a path that
    /// no longer exists is dropped). `nil` while the vault folder is gone: the caller keeps `known`,
    /// because a vanished folder is not a batch of deleted files.
    static func refresh(_ known: [String: Entry], touched: Set<String>, root: URL,
                        hashProvider: (URL) -> String? = { PollingFileWatcher.sha256Hex(ofFileAt: $0) }) -> [String: Entry]? {
        guard rootIsAvailable(root) else { return nil }
        var next = known
        for rel in touched {
            next[rel] = consistentEntry(at: root.appendingPathComponent(rel), hashProvider: hashProvider)
        }
        return next
    }

    /// Time, size and hash of the file at `url` taken from one version of it (`nil` when it is gone).
    /// Reading the time and then the bytes can straddle a write, giving the old time with the new
    /// hash; the next look then sees "same content, new time" and reports the app's own write as an
    /// outside change. So the time is read before and after hashing, and again while it moved.
    static func consistentEntry(at url: URL, hashProvider: (URL) -> String?) -> Entry? {
        func stamp() -> (mtime: Date, size: Int)? {
            guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
            return ((a[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0), (a[.size] as? NSNumber)?.intValue ?? 0)
        }
        var entry: Entry?
        for _ in 0..<5 {
            guard let before = stamp() else { return nil }
            let hash = hashProvider(url)
            guard let after = stamp() else { return nil }
            entry = Entry(mtime: after.mtime, size: after.size, hash: hash)
            if before.mtime == after.mtime, before.size == after.size { break }
        }
        return entry
    }

    static func isWatched(components: [String]) -> Bool {
        guard let last = components.last else { return false }
        if components.contains(where: { $0.hasPrefix(".") }) { return false }
        if last.lowercased().hasSuffix(".md") { return true }
        return components.dropLast().contains("_files")
    }
}
