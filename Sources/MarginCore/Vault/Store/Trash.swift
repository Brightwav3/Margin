import Foundation

/// Where "deleted" vault items go. MarginCore never hard-deletes a user file (spec 05 §10).
public protocol Trash: Sendable {
    /// Moves the file or folder at `url` (which lives inside the vault at `vaultRoot`) to the
    /// trash and returns where it ended up when known. Must not destroy the item on failure.
    func moveToTrash(itemAt url: URL, vaultRoot: URL, fileSystem: any FileSystem, clock: any Clock) throws -> URL?
}

/// Portable trash for Linux, tests and sandboxed builds: moves the item to
/// `<vault>/.margin/trash/<UTC timestamp>-<name>`. Nothing is ever deleted; the user (or a later
/// "empty trash" feature) removes it.
public struct PortableTrash: Trash {
    public init() {}

    /// Folder name below `.margin/`.
    public static let folderName = "trash"

    /// `yyyyMMdd'T'HHmmss'Z'` in UTC, derived from `date` without any formatter state.
    static func stamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ v: Int?, _ width: Int) -> String {
            let s = String(v ?? 0)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(c.year, 4))\(pad(c.month, 2))\(pad(c.day, 2))T\(pad(c.hour, 2))\(pad(c.minute, 2))\(pad(c.second, 2))Z"
    }

    public func moveToTrash(itemAt url: URL, vaultRoot: URL, fileSystem: any FileSystem, clock: any Clock) throws -> URL? {
        let folder = vaultRoot
            .appendingPathComponent(VaultPath.internalFolderName, isDirectory: true)
            .appendingPathComponent(Self.folderName, isDirectory: true)
        try fileSystem.createDirectories(at: folder)
        let stamp = Self.stamp(clock.now)
        let name = url.lastPathComponent
        var attempt = 1
        while true {
            let prefix = attempt == 1 ? stamp : "\(stamp)~\(attempt)"
            let destination = folder.appendingPathComponent("\(prefix)-\(name)")
            do {
                try fileSystem.moveItemNoReplace(from: url, to: destination)
                try? fileSystem.syncDirectory(at: folder)
                return destination
            } catch FileSystemError.alreadyExists {
                attempt += 1
                if attempt > 10_000 { throw FileSystemError.failed("trash: too many items with the same name and timestamp") }
            }
        }
    }
}

#if os(macOS)
/// The macOS Trash (`FileManager.trashItem`), so items can be restored from Finder.
public struct SystemTrash: Trash {
    public init() {}

    public func moveToTrash(itemAt url: URL, vaultRoot: URL, fileSystem: any FileSystem, clock: any Clock) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
}
#endif
