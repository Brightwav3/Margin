import Foundation
import MarginCore

/// A vault the app knows (account popup › Switch vault, Manage vaults 3a).
public struct VaultChoice: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isCurrent: Bool

    public init(name: String, path: String, isCurrent: Bool) {
        self.name = name; self.path = path; self.isCurrent = isCurrent
    }
}

/// What the app does with vault folders; MarginUI only asks (the app owns files and bookmarks).
@MainActor public protocol VaultSwitching: AnyObject {
    /// Recent vaults, the open one first.
    func recentVaults() -> [VaultChoice]
    /// Opens a recent vault in this window.
    func open(_ vault: VaultChoice)
    /// Open folder as vault…
    func openFolder()
    /// Create new vault…
    func createVault()
    /// Takes a vault off the list; its files stay on disk.
    func removeFromList(_ vault: VaultChoice)
    /// Shows the open vault in Finder.
    func revealVault()
}

/// Whether open notes and course pages follow edits made outside Margin (Settings › Vault and files).
@MainActor public enum ExternalChanges {
    public static var followed = true
}
