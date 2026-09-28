import Foundation
@testable import MarginCore

/// Wraps a real file system and fails at one chosen step, either with an error
/// (`.error`: the process survives, the store may clean up) or as a simulated violent
/// interruption (`.crash`: every later call also fails, so no cleanup code can run, exactly like a
/// killed process or a power cut). Fail points are addressed by the index of the call.
final class FaultInjectingFileSystem: FileSystem, @unchecked Sendable {
    enum Mode: Sendable { case error, crash }

    struct Fault: Sendable {
        var index: Int
        /// `false`: fail instead of executing the call. `true`: execute it, then fail.
        var afterExecuting: Bool
        var mode: Mode
        /// For `createFile` only (with `afterExecuting == false`): write half the bytes first.
        var partialWrite = false
    }

    private let base: any FileSystem
    private let lock = NSLock()
    private var counter = 0
    private var fault: Fault?
    private var crashed = false
    private var calls: [String] = []

    init(base: any FileSystem = POSIXFileSystem()) { self.base = base }

    /// Names of the calls since the last `arm`/`resetCounter`, in order.
    var log: [String] { lock.withLock { calls } }
    var opCount: Int { lock.withLock { counter } }

    func arm(_ fault: Fault?) {
        lock.withLock { self.fault = fault; counter = 0; calls = []; crashed = false }
    }

    func resetCounter() { arm(nil) }

    /// Brings the "process" back after a simulated crash.
    func revive() { lock.withLock { crashed = false; fault = nil } }

    private func step<T>(_ name: String, partial: (() throws -> Void)? = nil, _ body: () throws -> T) throws -> T {
        let decision: (hit: Fault?, dead: Bool) = lock.withLock {
            if crashed { return (nil, true) }
            let idx = counter
            counter += 1
            calls.append(name)
            if let f = fault, f.index == idx { return (f, false) }
            return (nil, false)
        }
        if decision.dead { throw FileSystemError.failed("simulated crash: process is dead (\(name))") }
        guard let f = decision.hit else { return try body() }
        if f.afterExecuting {
            _ = try body()
        } else if f.partialWrite, let partial {
            try partial()
        }
        if f.mode == .crash { lock.withLock { crashed = true } }
        throw FileSystemError.failed("injected fault at call \(f.index) (\(name), afterExecuting: \(f.afterExecuting), partial: \(f.partialWrite))")
    }

    func attributes(at url: URL) throws -> FileAttributes? { try step("attributes") { try base.attributes(at: url) } }
    func realPath(_ url: URL) throws -> URL { try step("realPath") { try base.realPath(url) } }
    func readData(at url: URL) throws -> Data { try step("readData") { try base.readData(at: url) } }
    func createDirectories(at url: URL) throws { try step("createDirectories") { try base.createDirectories(at: url) } }
    func createFile(at url: URL, data: Data, permissions: UInt16?) throws {
        try step("createFile", partial: {
            try self.base.createFile(at: url, data: Data(data.prefix(data.count / 2)), permissions: permissions)
        }) { try base.createFile(at: url, data: data, permissions: permissions) }
    }
    func sync(fileAt url: URL) throws { try step("sync") { try base.sync(fileAt: url) } }
    func syncDirectory(at url: URL) throws { try step("syncDirectory") { try base.syncDirectory(at: url) } }
    func replaceItem(at destination: URL, withItemAt source: URL) throws {
        try step("replaceItem") { try base.replaceItem(at: destination, withItemAt: source) }
    }
    func moveItemNoReplace(from source: URL, to destination: URL) throws {
        try step("moveItemNoReplace") { try base.moveItemNoReplace(from: source, to: destination) }
    }
    func removeFile(at url: URL) throws { try step("removeFile") { try base.removeFile(at: url) } }
    func contentsOfDirectory(at url: URL) throws -> [DirectoryEntry] { try step("contentsOfDirectory") { try base.contentsOfDirectory(at: url) } }
}
