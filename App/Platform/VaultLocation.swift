#if os(macOS)
import AppKit
import Foundation

/// Where the vault lives, remembered across launches of the sandboxed app with a security-scoped
/// bookmark (D-017: default `~/Documents/Margin`, chosen by the user in an open panel).
@MainActor
public enum VaultLocation {
    private static let bookmarkKey = "vault.bookmark"

    /// The remembered vault, with sandbox access started; nil when none is remembered or the
    /// folder is gone.
    public static func restore() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        remember(url)   // refreshes a stale bookmark and keeps the vault first in the recents
        return url
    }

    /// Asks for the vault folder, suggesting `~/Documents/Margin` (the user can create it in the panel).
    public static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as vault"
        panel.message = "Choose the folder for your notes. Margin keeps them as Markdown files there (Obsidian can open it too). Create “Margin” in Documents for a new vault."
        // In the sandbox NSHomeDirectory() is the container; the real home comes from the user record.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let documents = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Documents")
        panel.directoryURL = documents.appendingPathComponent("Margin")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        remember(url)
        return url
    }

    public static func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Makes `url` the vault opened at launch and puts it first in the recent vaults.
    public static func remember(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        var list = recentEntries().filter { $0.path != url.path }
        list.insert(RecentEntry(path: url.path, bookmark: data, opened: Date()), at: 0)
        save(Array(list.prefix(12)))
    }

    // MARK: Recent vaults (account popup › Switch vault, Manage vaults 3a)

    /// A vault opened before: its folder name, path and when it was last opened.
    public struct Recent: Identifiable, Sendable, Hashable {
        public var id: String { path }
        public let name: String
        public let path: String
        public let opened: Date
    }

    private struct RecentEntry: Codable {
        var path: String
        var bookmark: Data
        var opened: Date
    }

    private static let recentsKey = "vault.recents"

    private static func recentEntries() -> [RecentEntry] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let list = try? JSONDecoder().decode([RecentEntry].self, from: data) else { return [] }
        return list
    }

    private static func save(_ list: [RecentEntry]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: recentsKey) }
    }

    /// Recent vaults, last opened first.
    public static func recents() -> [Recent] {
        recentEntries().map { Recent(name: URL(fileURLWithPath: $0.path).lastPathComponent, path: $0.path, opened: $0.opened) }
    }

    /// Resolves a recent vault with sandbox access; nil when its folder is gone.
    public static func resolve(_ recent: Recent) -> URL? {
        guard let entry = recentEntries().first(where: { $0.path == recent.path }) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: entry.bookmark, options: [.withSecurityScope], relativeTo: nil,
                                 bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    /// Takes a vault off the list. The folder and its files stay on disk (3b).
    public static func removeFromList(_ recent: Recent) {
        save(recentEntries().filter { $0.path != recent.path })
    }

    /// Asks for a name and place, makes the folder and remembers it (3a „Create new vault“).
    public static func createNew() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create new vault"
        panel.prompt = "Create"
        panel.nameFieldLabel = "Vault name:"
        panel.nameFieldStringValue = "Margin"
        panel.message = "A new folder for Markdown notes. Margin keeps everything in it."
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch { return nil }
        _ = url.startAccessingSecurityScopedResource()
        remember(url)
        return url
    }

    /// Shows the vault folder in Finder.
    public static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
#endif
