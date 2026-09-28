import Foundation
import Testing
@testable import MarginCore

/// A throwaway vault folder in the system temp directory, removed when the value is released.
final class TempDir: @unchecked Sendable {
    let url: URL
    init() {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("margin-vault-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    func file(_ relative: String) -> URL { url.appendingPathComponent(relative) }
    func bytes(_ relative: String) -> Data? { FileManager.default.contents(atPath: file(relative).path) }
    func exists(_ relative: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: file(relative).path, isDirectory: &isDir)
    }
    func seed(_ relative: String, _ data: Data, permissions: Int? = nil) throws {
        let u = file(relative)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u)
        if let permissions { try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: u.path) }
    }
    /// Every regular file below the folder (hidden ones included) as relative path -> bytes.
    func snapshot() -> [String: Data] {
        var result: [String: Data] = [:]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return result }
        let base = url.resolvingSymlinksInPath().path
        for case let u as URL in e {
            let full = u.resolvingSymlinksInPath().path
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            result[String(full.dropFirst(base.count + 1))] = FileManager.default.contents(atPath: u.path)
        }
        return result
    }
    var temporaryFiles: [String] { snapshot().keys.filter { $0.split(separator: "/").last.map { VaultStore.isTemporaryName(String($0)) } ?? false }.sorted() }
}

func vp(_ s: String) -> VaultPath {
    do { return try VaultPath(s) } catch { fatalError("bad test path \(s)") }
}

/// A test file whose bytes would be damaged by any lossy handling: BOM, CRLF, non-ASCII, and
/// enough volume that a partial write is visibly partial.
func trickyBytes(seed: String = "orig", kilobytes: Int = 64) -> Data {
    var d = Data([0xEF, 0xBB, 0xBF])
    let line = "\(seed) — Příliš žluťoučký kůň 🧬 - [ ] task ^t-1\r\n"
    while d.count < kilobytes * 1024 { d.append(Data(line.utf8)) }
    return d
}
