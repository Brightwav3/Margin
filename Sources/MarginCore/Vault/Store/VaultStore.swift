import Foundation

/// The only component that touches the vault's files (spec 05 §1, §10, §12).
///
/// Guarantees:
/// - **Atomic writes:** content goes to a temporary file in the same folder, is fsynced, and only
///   then renamed over the target. A crash or error at any step leaves the previous file
///   byte-for-byte intact; leftover temporaries are invisible to `list` and removed on the next
///   `open`.
/// - **Optimistic concurrency:** `write(expectedVersion:)` fails with `MarginError.conflict` when
///   the file changed since the caller read it.
/// - **Never hard-deletes:** `trash` moves items to the trash (macOS Trash, or
///   `.margin/trash/` elsewhere).
/// - **Contained:** paths are `VaultPath`s and symlinks that lead outside the vault are refused.
///
/// Known limits (documented, not silent): replacing a file by rename gives it a new inode, so on
/// macOS the creation date, extended attributes (Finder tags) and hard links of the original are
/// not carried over. Permission bits are preserved.
public actor VaultStore {
    /// Vault root as given (location is provisional: configurable path, see Q1).
    public nonisolated let root: URL
    /// Temporary files found and removed by `open`.
    public private(set) var recoveredTemporaryFiles: [VaultPath] = []

    private let rootReal: String
    private let fileSystem: any FileSystem
    private let clock: any Clock
    private let trashService: any Trash
    private let ownWrites: OwnWriteRegistry?
    private var renameObservers: [any RenameObserver] = []

    static let temporarySuffix = ".margin-tmp"

    private init(root: URL, rootReal: String, fileSystem: any FileSystem, clock: any Clock, trash: any Trash, ownWrites: OwnWriteRegistry?) {
        self.root = root
        self.rootReal = rootReal
        self.fileSystem = fileSystem
        self.clock = clock
        self.trashService = trash
        self.ownWrites = ownWrites
    }

    /// Opens the vault at `root`, removing temporary files left behind by an interrupted write.
    ///
    /// - Parameters:
    ///   - createIfMissing: creates the folder when absent (otherwise `MarginError.notFound`).
    ///   - ownWrites: when given, every write, rename and trash is announced to this registry right
    ///     before it happens, so a `FileWatcher` sharing it does not report the app's own changes.
    ///   - trash: defaults to the macOS Trash on macOS and `PortableTrash` elsewhere.
    public static func open(
        root: URL,
        fileSystem: any FileSystem = POSIXFileSystem(),
        clock: any Clock = SystemClock(),
        trash: (any Trash)? = nil,
        createIfMissing: Bool = false,
        ownWrites: OwnWriteRegistry? = nil
    ) async throws -> VaultStore {
        let root = root.standardizedFileURL
        do {
            if try fileSystem.attributes(at: root) == nil {
                guard createIfMissing else { throw MarginError.notFound("Vault folder does not exist: \(root.lastPathComponent)") }
                try fileSystem.createDirectories(at: root)
            }
            let real = try fileSystem.realPath(root)
            guard try fileSystem.attributes(at: real)?.kind == .directory else {
                throw MarginError.invalid("Vault root is not a folder: \(root.lastPathComponent)")
            }
            #if os(macOS)
            let defaultTrash: any Trash = SystemTrash()
            #else
            let defaultTrash: any Trash = PortableTrash()
            #endif
            let store = VaultStore(root: root, rootReal: real.path, fileSystem: fileSystem, clock: clock, trash: trash ?? defaultTrash, ownWrites: ownWrites)
            await store.recoverTemporaryFiles()
            return store
        } catch { throw VaultStore.map(error, "open vault") }
    }

    /// Registers a hook that runs after every successful rename or move.
    public func addRenameObserver(_ observer: any RenameObserver) {
        renameObservers.append(observer)
    }

    // MARK: - Reading

    /// Reads a note. `version` is the SHA-256 of the exact bytes, to be passed back as
    /// `expectedVersion`. Throws `.invalid` if the file is not valid UTF-8 (it is never decoded
    /// lossily, so a later write cannot corrupt it).
    public func read(_ path: VaultPath) throws -> (content: String, version: ContentHash) {
        let (data, version) = try readData(path)
        guard let text = String(validating: data, as: UTF8.self) else {
            throw MarginError.invalid("\(path) is not valid UTF-8 text")
        }
        return (text, version)
    }

    /// Reads raw bytes and their version.
    public func readData(_ path: VaultPath) throws -> (data: Data, version: ContentHash) {
        do {
            let url = try checkedURL(path, followFinal: true)
            guard let attrs = try fileSystem.attributes(at: url) else { throw MarginError.notFound("No such file: \(path)") }
            guard attrs.kind != .directory else { throw MarginError.invalid("\(path) is a folder, not a file") }
            let data = try fileSystem.readData(at: url)
            return (data, ContentHash(of: data))
        } catch { throw VaultStore.map(error, "read \(path)") }
    }

    /// Current version of a file, or `nil` when it does not exist.
    public func version(of path: VaultPath) throws -> ContentHash? {
        do {
            let url = try checkedURL(path, followFinal: true)
            guard try fileSystem.attributes(at: url) != nil else { return nil }
            return try readData(path).version
        } catch { throw VaultStore.map(error, "version \(path)") }
    }

    /// `true` when a file or folder exists at `path` (a failing check counts as absent).
    public func exists(_ path: VaultPath) -> Bool {
        guard let url = try? checkedURL(path, followFinal: false) else { return false }
        return ((try? fileSystem.attributes(at: url)) ?? nil) != nil
    }

    /// Markdown files (`.md`) below `folder` (whole vault when `nil`), sorted by path. Dotfiles and
    /// dot-folders (so `.margin/`, `.obsidian/`, temporary files) and symlinks are skipped.
    public func list(under folder: VaultPath? = nil) throws -> [VaultPath] {
        var result: [VaultPath] = []
        var stack: [[String]] = [folder?.components ?? []]
        do {
            if let folder {
                let url = try checkedURL(folder, followFinal: true)
                guard let attrs = try fileSystem.attributes(at: url) else { throw MarginError.notFound("No such folder: \(folder)") }
                guard attrs.kind == .directory else { throw MarginError.invalid("\(folder) is not a folder") }
                if folder.isHidden { return [] }
            }
            while let dir = stack.popLast() {
                let dirURL = url(forComponents: dir)
                for entry in try fileSystem.contentsOfDirectory(at: dirURL) {
                    if entry.name.hasPrefix(".") { continue }
                    switch entry.kind {
                    case .directory:
                        stack.append(dir + [entry.name])
                    case .file:
                        if entry.name.lowercased().hasSuffix(".md"), let p = try? VaultPath(components: dir + [entry.name]) {
                            result.append(p)
                        }
                    case .symlink, .other:
                        continue
                    }
                }
            }
        } catch { throw VaultStore.map(error, "list") }
        return result.sorted()
    }

    // MARK: - Writing

    /// Atomically writes `content` to `path`, creating the file and missing folders when needed.
    ///
    /// - Parameter expectedVersion: when given, the file must exist and still have this version,
    ///   otherwise `MarginError.conflict` and nothing is written.
    /// - Returns: the version of the newly written file.
    @discardableResult
    public func write(_ path: VaultPath, content: String, expectedVersion: ContentHash? = nil) async throws -> ContentHash {
        try await atomicWrite(Data(content.utf8), to: path, expectedVersion: expectedVersion, mustNotExist: false)
    }

    /// Byte-level variant of `write`.
    @discardableResult
    public func writeData(_ path: VaultPath, data: Data, expectedVersion: ContentHash? = nil) async throws -> ContentHash {
        try await atomicWrite(data, to: path, expectedVersion: expectedVersion, mustNotExist: false)
    }

    /// Creates a new file; `MarginError.conflict` when something already exists at `path`.
    @discardableResult
    public func create(_ path: VaultPath, content: String) async throws -> ContentHash {
        try await atomicWrite(Data(content.utf8), to: path, expectedVersion: nil, mustNotExist: true)
    }

    /// Byte-level variant of `create`.
    @discardableResult
    public func createData(_ path: VaultPath, data: Data) async throws -> ContentHash {
        try await atomicWrite(data, to: path, expectedVersion: nil, mustNotExist: true)
    }

    /// Renames or moves a file or folder, creating missing target folders. `MarginError.conflict`
    /// when the target exists (nothing is overwritten), `.notFound` when the source is missing.
    /// Registered `RenameObserver`s run after the move, unless `notifyObservers` is `false`: the
    /// change-set journal replays recorded operations literally (the link rewrites a rename caused
    /// are recorded as operations of their own), so a replayed rename must not rewrite links again.
    public func rename(_ from: VaultPath, to: VaultPath, notifyObservers: Bool = true) async throws {
        guard from != to else { return }
        let isDirectory: Bool
        var announced: [(path: String, hash: String)] = []
        do {
            for p in [from, to] where VaultStore.isTrashArea(p) {
                throw MarginError.invalid("\(p) is inside the trash area and cannot be renamed")
            }
            if from == VaultPath.internalRoot {
                throw MarginError.invalid("The .margin folder cannot be renamed")
            }
            if to.isInside(from) { throw MarginError.invalid("Cannot move \(from) into itself") }
            let source = try checkedURL(from, followFinal: false)
            let target = try checkedURL(to, followFinal: false)
            guard let sourceAttrs = try fileSystem.attributes(at: source) else { throw MarginError.notFound("No such file: \(from)") }
            isDirectory = sourceAttrs.kind == .directory
            if let capture = WriteCaptureContext.current {
                try await capture.willApply(.move(from: from, to: to))
            }
            let targetParent = target.deletingLastPathComponent()
            try fileSystem.createDirectories(at: targetParent)
            if let ownWrites {
                // Announce before the move: the source disappears and the same bytes appear at the target.
                for file in watchedFiles(at: source, path: from) {
                    let moved = to.rawValue + file.path.dropFirst(from.rawValue.count)
                    announced.append((file.path, OwnWriteRegistry.deletedHash))
                    announced.append((moved, file.hash))
                }
                for a in announced { await ownWrites.register(path: a.path, hash: a.hash) }
            }
            do {
                try fileSystem.moveItemNoReplace(from: source, to: target)
            } catch FileSystemError.alreadyExists {
                // Case-only rename on a case-insensitive volume: the "existing target" is the
                // source itself. Renaming a file onto itself cannot lose data.
                if let t = try fileSystem.attributes(at: target), t.inode == sourceAttrs.inode, t.device == sourceAttrs.device,
                   from.rawValue.lowercased() == to.rawValue.lowercased() {
                    try fileSystem.replaceItem(at: target, withItemAt: source)
                } else {
                    throw MarginError.conflict("Cannot rename \(from) to \(to): target already exists")
                }
            }
            try? fileSystem.syncDirectory(at: targetParent)
            let sourceParent = source.deletingLastPathComponent()
            if sourceParent != targetParent { try? fileSystem.syncDirectory(at: sourceParent) }
        } catch {
            if let ownWrites { for a in announced { await ownWrites.forget(path: a.path, hash: a.hash) } }
            throw VaultStore.map(error, "rename \(from)")
        }

        guard notifyObservers else { return }
        for observer in renameObservers {
            await observer.vaultDidRename(from: from, to: to, isDirectory: isDirectory, in: self)
        }
    }

    /// Moves a file or folder to the trash. Nothing is ever hard-deleted. Returns the item's new
    /// location when the trash reports it.
    @discardableResult
    public func trash(_ path: VaultPath) async throws -> URL? {
        var announced: [String] = []
        do {
            if VaultStore.isTrashArea(path) || path == VaultPath.internalRoot {
                throw MarginError.invalid("\(path) is app data and cannot be trashed")
            }
            let url = try checkedURL(path, followFinal: false)
            guard let attrs = try fileSystem.attributes(at: url) else { throw MarginError.notFound("No such file: \(path)") }
            if let capture = WriteCaptureContext.current {
                let isFile = attrs.kind == .file
                try await capture.willApply(.trash(path: path, before: isFile ? try fileSystem.readData(at: url) : nil,
                                                   isRegularFile: isFile))
            }
            if let ownWrites {
                announced = watchedFiles(at: url, path: path).map(\.path)
                for p in announced { await ownWrites.register(path: p, hash: OwnWriteRegistry.deletedHash) }
            }
            let destination = try trashService.moveToTrash(itemAt: url, vaultRoot: root, fileSystem: fileSystem, clock: clock)
            try? fileSystem.syncDirectory(at: url.deletingLastPathComponent())
            return destination
        } catch {
            if let ownWrites { for p in announced { await ownWrites.forget(path: p, hash: OwnWriteRegistry.deletedHash) } }
            throw VaultStore.map(error, "trash \(path)")
        }
    }

    // MARK: - App data (.margin)

    /// Names of the regular files directly inside `folder` (a folder below `.margin/`), sorted; an
    /// absent folder has none. Used by the change-set journal, which is the only reader of its own
    /// folder.
    func appDataFileNames(in folder: VaultPath) throws -> [String] {
        guard folder.isInternal else { throw MarginError.invalid("\(folder) is not app data") }
        do {
            let url = try checkedURL(folder, followFinal: true)
            guard let attrs = try fileSystem.attributes(at: url) else { return [] }
            guard attrs.kind == .directory else { throw MarginError.invalid("\(folder) is not a folder") }
            return try fileSystem.contentsOfDirectory(at: url).filter { $0.kind == .file }.map(\.name).sorted()
        } catch { throw VaultStore.map(error, "list \(folder)") }
    }

    /// Deletes one file of the change-set journal (`.margin/changesets/`). This is the only
    /// deletion the store performs besides its own temporary files: journal records are app data,
    /// never user content, and expire by the retention rule.
    func removeJournalFile(_ path: VaultPath) throws {
        guard path.isInside(VaultPath.internalChangeSets), path != VaultPath.internalChangeSets else {
            throw MarginError.invalid("\(path) is not a change-set record")
        }
        do {
            let url = try checkedURL(path, followFinal: false)
            guard try fileSystem.attributes(at: url) != nil else { return }
            try fileSystem.removeFile(at: url)
        } catch { throw VaultStore.map(error, "remove \(path)") }
    }

    // MARK: - Atomic write pipeline

    private func atomicWrite(_ data: Data, to path: VaultPath, expectedVersion: ContentHash?, mustNotExist: Bool) async throws -> ContentHash {
        let parent: URL
        let newHash = ContentHash(of: data)
        var announced = false
        do {
            if VaultStore.isTrashArea(path) { throw MarginError.invalid("\(path) is inside the trash area") }
            let target = try checkedURL(path, followFinal: false)
            let existing = try fileSystem.attributes(at: target)
            if let existing {
                if mustNotExist { throw MarginError.conflict("\(path) already exists") }
                switch existing.kind {
                case .file: break
                case .directory: throw MarginError.invalid("\(path) is a folder")
                case .symlink: throw MarginError.invalid("Refusing to write through the symlink \(path)")
                case .other: throw MarginError.invalid("\(path) is not a regular file")
                }
            }
            if let expectedVersion {
                guard existing != nil else { throw MarginError.conflict("\(path) no longer exists (expected version \(expectedVersion))") }
                try verify(version: expectedVersion, of: target, path: path)
            }

            if let capture = WriteCaptureContext.current {
                // Write-ahead: the bytes about to be replaced are persisted by the recorder before
                // anything is written. They are also what `expectedVersion` was checked against.
                let before: Data? = existing == nil ? nil : try fileSystem.readData(at: target)
                if let expectedVersion, let before, ContentHash(of: before) != expectedVersion {
                    throw MarginError.conflict("\(path) changed on disk (expected \(expectedVersion.hex.prefix(12)), found \(ContentHash(of: before).hex.prefix(12)))",
                                               ConflictDetail(path: path.rawValue, currentVersion: ContentHash(of: before).hex))
                }
                try await capture.willApply(.write(path: path, before: before, after: data))
            }

            parent = target.deletingLastPathComponent()
            try fileSystem.createDirectories(at: parent)
            let temp = parent.appendingPathComponent(".\(UUID().uuidString)\(VaultStore.temporarySuffix)")
            do {
                if let ownWrites, VaultStore.isWatched(path) {
                    await ownWrites.register(path: path.rawValue, hash: newHash)
                    announced = true
                }
                try fileSystem.createFile(at: temp, data: data, permissions: existing?.permissions)
                try fileSystem.sync(fileAt: temp)
                // Narrow the check-to-rename window for writers outside this process.
                if let expectedVersion { try verify(version: expectedVersion, of: target, path: path) }
                if mustNotExist {
                    try fileSystem.moveItemNoReplace(from: temp, to: target)
                } else {
                    try fileSystem.replaceItem(at: target, withItemAt: temp)
                }
            } catch {
                try? fileSystem.removeFile(at: temp)
                throw error
            }
        } catch {
            if announced, let ownWrites { await ownWrites.forget(path: path.rawValue, hash: newHash) }
            throw VaultStore.map(error, "write \(path)")
        }

        do { try fileSystem.syncDirectory(at: parent) } catch {
            throw MarginError.io("\(path) was written but syncing its folder failed: \(error)")
        }
        return newHash
    }

    private func verify(version expected: ContentHash, of target: URL, path: VaultPath) throws {
        let current: Data
        do { current = try fileSystem.readData(at: target) } catch FileSystemError.notFound {
            throw MarginError.conflict("\(path) no longer exists (expected version \(expected))", ConflictDetail(path: path.rawValue))
        }
        let actual = ContentHash(of: current)
        guard actual == expected else {
            throw MarginError.conflict("\(path) changed on disk (expected \(expected.hex.prefix(12)), found \(actual.hex.prefix(12)))",
                                       ConflictDetail(path: path.rawValue, currentVersion: actual.hex))
        }
    }

    // MARK: - Own-write announcements

    private static func isWatched(_ path: VaultPath) -> Bool {
        PollingFileWatcher.isWatched(components: path.components)
    }

    /// Files the watcher would report below (or at) `url`, with the hash of their current bytes.
    private func watchedFiles(at url: URL, path: VaultPath) -> [(path: String, hash: String)] {
        guard let attrs = try? fileSystem.attributes(at: url) else { return [] }
        switch attrs.kind {
        case .file:
            guard VaultStore.isWatched(path), let data = try? fileSystem.readData(at: url) else { return [] }
            return [(path.rawValue, ContentHash(of: data).hex)]
        case .directory:
            guard let entries = try? fileSystem.contentsOfDirectory(at: url) else { return [] }
            var out: [(path: String, hash: String)] = []
            for entry in entries where !entry.name.hasPrefix(".") {
                guard let child = try? VaultPath(components: path.components + [entry.name]) else { continue }
                out += watchedFiles(at: url.appendingPathComponent(entry.name), path: child)
            }
            return out
        case .symlink, .other:
            return []
        }
    }

    // MARK: - Path handling

    private func url(forComponents components: [String]) -> URL {
        components.isEmpty ? root : root.appendingPathComponent(components.joined(separator: "/"))
    }

    /// The file URL for `path`, after checking that resolving symlinks keeps it inside the vault.
    /// With `followFinal == false` the last component itself may be a symlink (it is acted on, not
    /// followed), so only its parent chain is resolved.
    private func checkedURL(_ path: VaultPath, followFinal: Bool) throws -> URL {
        var probe = path.components
        if !followFinal { probe.removeLast() }
        while !probe.isEmpty {
            let candidate = url(forComponents: probe)
            if try fileSystem.attributes(at: candidate) != nil {
                let real: URL
                do { real = try fileSystem.realPath(candidate) } catch FileSystemError.notFound {
                    throw MarginError.invalid("\(path) goes through a dangling symlink")
                }
                guard real.path == rootReal || real.path.hasPrefix(rootReal.hasSuffix("/") ? rootReal : rootReal + "/") else {
                    throw MarginError.invalid("\(path) resolves outside the vault")
                }
                break
            }
            probe.removeLast()
        }
        return url(forComponents: path.components)
    }

    private static func isTrashArea(_ path: VaultPath) -> Bool {
        path.isInside(VaultPath.internalTrash)
    }

    // MARK: - Recovery

    /// Removes leftover `.<uuid>.margin-tmp` files from interrupted writes. Best effort: the
    /// originals were never touched, and an unacknowledged write has no owner.
    private func recoverTemporaryFiles() {
        var removed: [VaultPath] = []
        var stack: [[String]] = [[]]
        while let dir = stack.popLast() {
            guard let entries = try? fileSystem.contentsOfDirectory(at: url(forComponents: dir)) else { continue }
            for entry in entries {
                let components = dir + [entry.name]
                switch entry.kind {
                case .directory:
                    let hidden = entry.name.hasPrefix(".")
                    let isMargin = dir.isEmpty && entry.name == VaultPath.internalFolderName
                    let isTrash = dir == [VaultPath.internalFolderName] && entry.name == PortableTrash.folderName
                    if (!hidden || isMargin) && !isTrash { stack.append(components) }
                case .file:
                    if VaultStore.isTemporaryName(entry.name) {
                        do {
                            try fileSystem.removeFile(at: url(forComponents: components))
                            if let p = try? VaultPath(components: components) { removed.append(p) }
                        } catch { continue }
                    }
                case .symlink, .other:
                    continue
                }
            }
        }
        recoveredTemporaryFiles = removed.sorted()
    }

    static func isTemporaryName(_ name: String) -> Bool {
        guard name.hasPrefix("."), name.hasSuffix(temporarySuffix) else { return false }
        let middle = name.dropFirst().dropLast(temporarySuffix.count)
        return middle.count == 36 && UUID(uuidString: String(middle)) != nil
    }

    // MARK: - Errors

    private static func map(_ error: any Error, _ operation: String) -> MarginError {
        switch error {
        case let e as MarginError: e
        case FileSystemError.notFound(let m): .notFound(m)
        case FileSystemError.alreadyExists(let m): .conflict(m)
        case FileSystemError.failed(let m): .io(m)
        default: .io("\(operation): \(error)")
        }
    }
}

extension VaultPath {
    /// `.margin`
    static let internalRoot = VaultPath(unchecked: [internalFolderName])
    /// `.margin/changesets`
    static let internalChangeSets = VaultPath(unchecked: [internalFolderName, "changesets"])
    /// `.margin/trash`
    static let internalTrash = VaultPath(unchecked: [internalFolderName, PortableTrash.folderName])
}
