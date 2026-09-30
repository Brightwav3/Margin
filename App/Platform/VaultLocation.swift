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
        if stale { remember(url) }
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

    private static func remember(_ url: URL) {
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }
}
#endif
