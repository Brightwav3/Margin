import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Kind of a directory entry, from `lstat` (symlinks are not followed).
public enum FileKind: Sendable, Hashable {
    case file, directory, symlink, other
}

/// Result of `lstat` for one path.
public struct FileAttributes: Sendable, Hashable {
    public var kind: FileKind
    public var size: Int64
    /// POSIX permission bits (`0o7777` mask).
    public var permissions: UInt16
    /// Device and inode: identify one file irrespective of the spelling of its path.
    public var device: UInt64
    public var inode: UInt64

    public init(kind: FileKind, size: Int64, permissions: UInt16, device: UInt64, inode: UInt64) {
        self.kind = kind; self.size = size; self.permissions = permissions
        self.device = device; self.inode = inode
    }
}

/// One entry returned by `FileSystem.contentsOfDirectory`.
public struct DirectoryEntry: Sendable, Hashable {
    public var name: String
    public var kind: FileKind
    public init(name: String, kind: FileKind) { self.name = name; self.kind = kind }
}

/// Low-level failures a `FileSystem` reports; `VaultStore` maps them to `MarginError`.
public enum FileSystemError: Error, Sendable, Hashable {
    case notFound(String)
    case alreadyExists(String)
    case failed(String)
}

/// The narrow file-system surface `VaultStore` is built on. Every step of an atomic write is a
/// separate call so tests can inject a fault (or a simulated crash) between any two of them.
///
/// Implementations must be thread-safe. All URLs are file URLs.
public protocol FileSystem: Sendable {
    /// Metadata of the entry itself (`lstat`); `nil` when it does not exist.
    func attributes(at url: URL) throws -> FileAttributes?
    /// Canonical path with symlinks resolved.
    func realPath(_ url: URL) throws -> URL
    /// All bytes of a regular file (follows symlinks).
    func readData(at url: URL) throws -> Data
    /// Creates `url` and any missing parents; succeeds when it already is a directory.
    func createDirectories(at url: URL) throws
    /// Creates a NEW file (fails with `.alreadyExists` if present), writes all of `data`. Does not
    /// fsync. `permissions` are applied to the file when non-nil.
    func createFile(at url: URL, data: Data, permissions: UInt16?) throws
    /// Flushes a file's contents to stable storage.
    func sync(fileAt url: URL) throws
    /// Flushes a directory's entries (creations and renames) to stable storage.
    func syncDirectory(at url: URL) throws
    /// Atomically renames `source` over `destination`, replacing it if it exists (`rename(2)`).
    func replaceItem(at destination: URL, withItemAt source: URL) throws
    /// Moves `source` to `destination` and NEVER replaces an existing destination
    /// (`.alreadyExists` instead).
    func moveItemNoReplace(from source: URL, to destination: URL) throws
    /// Removes one file. Only used for the store's own temporary files.
    func removeFile(at url: URL) throws
    /// Entries of a directory (without `.` and `..`), in unspecified order.
    func contentsOfDirectory(at url: URL) throws -> [DirectoryEntry]
}

/// The real file system through POSIX calls.
public struct POSIXFileSystem: FileSystem {
    public init() {}

    private static func describe(_ op: String, _ url: URL, _ code: Int32) -> String {
        "\(op) \(url.lastPathComponent): \(String(cString: strerror(code))) (errno \(code))"
    }

    private static func fail(_ op: String, _ url: URL, _ code: Int32) -> FileSystemError {
        switch code {
        case ENOENT: .notFound(describe(op, url, code))
        case EEXIST, ENOTEMPTY: .alreadyExists(describe(op, url, code))
        default: .failed(describe(op, url, code))
        }
    }

    public func attributes(at url: URL) throws -> FileAttributes? {
        var st = stat()
        if lstat(url.path, &st) != 0 {
            let code = errno
            if code == ENOENT || code == ENOTDIR { return nil }
            throw Self.fail("stat", url, code)
        }
        let type = mode_t(st.st_mode) & mode_t(S_IFMT)
        let kind: FileKind
        if type == mode_t(S_IFREG) { kind = .file }
        else if type == mode_t(S_IFDIR) { kind = .directory }
        else if type == mode_t(S_IFLNK) { kind = .symlink }
        else { kind = .other }
        return FileAttributes(
            kind: kind, size: Int64(st.st_size),
            permissions: UInt16(truncatingIfNeeded: mode_t(st.st_mode) & 0o7777),
            device: UInt64(truncatingIfNeeded: st.st_dev), inode: UInt64(truncatingIfNeeded: st.st_ino))
    }

    public func realPath(_ url: URL) throws -> URL {
        guard let resolved = realpath(url.path, nil) else { throw Self.fail("realpath", url, errno) }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    public func readData(at url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw Self.fail("open", url, errno) }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw Self.fail("fstat", url, errno) }
        guard mode_t(st.st_mode) & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw FileSystemError.failed("read \(url.lastPathComponent): not a regular file")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                throw Self.fail("read", url, errno)
            }
            if n == 0 { break }
            data.append(contentsOf: buffer[0..<n])
        }
        return data
    }

    public func createDirectories(at url: URL) throws {
        // Walk down component by component so existing directories are not an error and a file
        // in the way is reported precisely.
        var current = url.path.hasPrefix("/") ? "/" : ""
        for part in url.path.split(separator: "/") {
            current = current.isEmpty || current == "/" ? current + part : current + "/" + part
            if mkdir(current, 0o777) != 0 {
                let code = errno
                if code == EEXIST {
                    var st = stat()
                    if stat(current, &st) == 0, mode_t(st.st_mode) & mode_t(S_IFMT) == mode_t(S_IFDIR) { continue }
                    throw FileSystemError.failed("mkdir \(part): exists and is not a directory")
                }
                throw Self.fail("mkdir", URL(fileURLWithPath: current), code)
            }
        }
    }

    public func createFile(at url: URL, data: Data, permissions: UInt16?) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o666)
        guard fd >= 0 else { throw Self.fail("create", url, errno) }
        defer { close(fd) }
        if let permissions, fchmod(fd, mode_t(permissions)) != 0 { throw Self.fail("chmod", url, errno) }
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw Self.fail("write", url, errno)
                }
                offset += n
            }
        }
    }

    public func sync(fileAt url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw Self.fail("open", url, errno) }
        defer { close(fd) }
        try Self.flush(fd, url)
    }

    public func syncDirectory(at url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw Self.fail("open", url, errno) }
        defer { close(fd) }
        do { try Self.flush(fd, url) } catch {
            // Some file systems refuse fsync on directories (EINVAL); that is not a failed write.
            if case FileSystemError.failed(let m) = error, m.contains("errno \(EINVAL)") { return }
            throw error
        }
    }

    private static func flush(_ fd: Int32, _ url: URL) throws {
        #if canImport(Darwin)
        // fsync on macOS does not reach the platter; F_FULLFSYNC does.
        if fcntl(fd, F_FULLFSYNC) == 0 { return }
        #endif
        while fsync(fd) != 0 {
            if errno == EINTR { continue }
            throw fail("fsync", url, errno)
        }
    }

    public func replaceItem(at destination: URL, withItemAt source: URL) throws {
        guard rename(source.path, destination.path) == 0 else { throw Self.fail("rename", destination, errno) }
    }

    public func moveItemNoReplace(from source: URL, to destination: URL) throws {
        // link(2) fails atomically with EEXIST, so an existing destination is never overwritten.
        // It only works for non-directories on file systems with hard links; otherwise fall back
        // to check-then-rename (safe inside the store's actor; external racers are out of scope).
        // Symlinks and directories skip link(2) (Darwin's link follows symlinks).
        var code: Int32 = EPERM
        if try attributes(at: source)?.kind == .file {
            if link(source.path, destination.path) == 0 {
                guard unlink(source.path) == 0 else { throw Self.fail("unlink", source, errno) }
                return
            }
            code = errno
        }
        if code == EEXIST { throw Self.fail("move", destination, code) }
        if code == ENOENT { throw Self.fail("move", source, code) }
        guard try attributes(at: source) != nil else { throw FileSystemError.notFound("move \(source.lastPathComponent): no such file") }
        if try attributes(at: destination) != nil { throw FileSystemError.alreadyExists("move \(destination.lastPathComponent): target exists") }
        guard rename(source.path, destination.path) == 0 else { throw Self.fail("rename", destination, errno) }
    }

    public func removeFile(at url: URL) throws {
        guard unlink(url.path) == 0 else { throw Self.fail("unlink", url, errno) }
    }

    public func contentsOfDirectory(at url: URL) throws -> [DirectoryEntry] {
        guard let dir = opendir(url.path) else { throw Self.fail("opendir", url, errno) }
        defer { closedir(dir) }
        var entries: [DirectoryEntry] = []
        while let ent = readdir(dir) {
            let name = withUnsafePointer(to: &ent.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            let attrs = try attributes(at: url.appendingPathComponent(name))
            entries.append(DirectoryEntry(name: name, kind: attrs?.kind ?? .other))
        }
        return entries
    }
}
