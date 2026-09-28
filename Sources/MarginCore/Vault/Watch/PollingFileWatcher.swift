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
        self.root = root.resolvingSymlinksInPath()
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
        let task = Task { [self] in
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
                // so same-size edits within one mtime tick are still noticed.
                entry.hash = hashProvider(url)
            } else {
                entry.hash = previous[path]?.hash
            }
            result[path] = entry
        }
        return result
    }

    static func isWatched(components: [String]) -> Bool {
        guard let last = components.last else { return false }
        if components.contains(where: { $0.hasPrefix(".") }) { return false }
        if last.lowercased().hasSuffix(".md") { return true }
        return components.dropLast().contains("_files")
    }
}
