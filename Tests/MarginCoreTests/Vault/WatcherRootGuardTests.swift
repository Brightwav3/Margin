import Foundation
import Testing
@testable import MarginCore

/// The missing-root rule (M12-03) that `PollingFileWatcher` and the macOS-only `FSEventsFileWatcher`
/// share (`rootIsAvailable`, `refresh`): a vanished vault folder never becomes a batch of deletions.
/// The FSEvents watcher itself is not compiled here (UNVERIFIED, M5-07); these cover its shared logic.
@Suite struct WatcherRootGuardTests {
    private func makeRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("margin-root-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Course"), withIntermediateDirectories: true)
        return dir.resolvingSymlinksInPath()
    }

    @Test func aFolderIsAvailableOnlyWhileItIsAFolder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PollingFileWatcher.rootIsAvailable(root))
        let file = root.appendingPathComponent("plain.txt")
        try Data("x".utf8).write(to: file)
        #expect(!PollingFileWatcher.rootIsAvailable(file))
        #expect(!PollingFileWatcher.rootIsAvailable(root.appendingPathComponent("nope")))
    }

    @Test func refreshKeepsNothingToDropWhileTheRootIsGone() throws {
        let root = try makeRoot()
        let file = root.appendingPathComponent("Course/a.md")
        try Data("# A\n".utf8).write(to: file)
        let known = try #require(PollingFileWatcher.refresh([:], touched: ["Course/a.md"], root: root))
        #expect(known.keys.sorted() == ["Course/a.md"] && known["Course/a.md"]?.hash != nil)

        let away = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-away")
        try FileManager.default.moveItem(at: root, to: away)
        defer { try? FileManager.default.removeItem(at: away); try? FileManager.default.removeItem(at: root) }
        // The file "does not exist" now, but the folder is what is missing: no answer, the caller keeps `known`.
        #expect(PollingFileWatcher.refresh(known, touched: ["Course/a.md"], root: root) == nil)

        try FileManager.default.moveItem(at: away, to: root)
        let back = try #require(PollingFileWatcher.refresh(known, touched: ["Course/a.md"], root: root))
        #expect(back["Course/a.md"]?.hash == known["Course/a.md"]?.hash)
    }

    @Test func refreshDropsAFileThatIsGoneWhileTheFolderIsThere() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Course/a.md")
        try Data("# A\n".utf8).write(to: file)
        let known = try #require(PollingFileWatcher.refresh([:], touched: ["Course/a.md"], root: root))
        try FileManager.default.removeItem(at: file)
        let next = try #require(PollingFileWatcher.refresh(known, touched: ["Course/a.md"], root: root))
        #expect(next.isEmpty)
    }

    @Test func aScanKeepsThePreviousSnapshotWhileTheRootIsGone() throws {
        let root = try makeRoot()
        try Data("# A\n".utf8).write(to: root.appendingPathComponent("Course/a.md"))
        let watcher = PollingFileWatcher(root: root)
        let known = watcher.scan(previous: [:])
        #expect(known.count == 1)
        let away = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-away")
        try FileManager.default.moveItem(at: root, to: away)
        defer { try? FileManager.default.removeItem(at: away); try? FileManager.default.removeItem(at: root) }
        #expect(watcher.scan(previous: known) == known)
    }
}
