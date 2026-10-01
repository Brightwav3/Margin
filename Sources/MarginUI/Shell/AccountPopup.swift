import MarginCore
import SwiftUI

/// The avatar at the bottom of the rail; a click opens the account popup (Margin Account v3 1a–1c).
struct AccountButton: View {
    let initials: String
    @Environment(Workspace.self) private var workspace: Workspace?
    @State private var open = false
    @State private var hovered = false

    var body: some View {
        Button { if workspace != nil { open.toggle() } } label: {
            Avatar(initials: initials, size: 30)
                .overlay { Circle().strokeBorder(.white.opacity(hovered ? 0.6 : 0), lineWidth: 2) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .marginTooltip("Profile, vault and settings")
        .accessibilityLabel("Account and vault")
        .popover(isPresented: $open, arrowEdge: .trailing) {
            if let workspace { AccountPopup(close: { open = false }).environment(workspace) }
        }
    }
}

/// 1a: who this vault belongs to, that it is saved on this Mac, and the account and vault actions.
struct AccountPopup: View {
    let close: () -> Void
    @Environment(Workspace.self) private var workspace
    @State private var showVaults = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                MarginDivider().padding(.vertical, 6)
                row("Profile", icon: "person") { settings(.profile) }
                row("Vault and files", icon: "folder", meta: workspace.vaultURL?.lastPathComponent ?? "Sample") { settings(.vault) }
                row("File recovery", icon: "history") { settings(.vault) }
                row("Sync", icon: "sync", meta: "Off") { settings(.sync) }
                MarginDivider().padding(.vertical, 6)
                row("Settings…", icon: "settings", shortcut: "⌘,") { settings(.general) }
                row("Keyboard shortcuts", icon: "keyboard", shortcut: "⌘/") { close(); workspace.dialog = .help(.shortcuts) }
                MarginDivider().padding(.vertical, 6)
                row("Switch vault", icon: "swap_horiz", submenu: true, active: showVaults) { showVaults.toggle() }
                    .disabled(workspace.vaults == nil)
                row("Sign in…", icon: "login", meta: "Optional") { settings(.signIn) }
            }
            .padding(8)
            .frame(width: 300)
            if showVaults { vaultList }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(initials: workspace.profile.initials, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.profile.name.isEmpty ? "Your profile" : workspace.profile.name).marginFont(MarginTextSize.base, .semibold)
                Text(workspace.vaultURL.map { "\($0.lastPathComponent) vault" } ?? "Sample data").marginFont(MarginTextSize.sm)
                    .foregroundStyle(MarginColor.textSecondary)
                HStack(spacing: 5) {
                    Circle().fill(MarginColor.textTertiary).frame(width: 6, height: 6)
                    Text(workspace.vaultURL == nil ? "Not saved to disk" : "Saved on this Mac").marginFont(MarginTextSize.xs)
                        .foregroundStyle(MarginColor.textSecondary)
                }
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(MarginColor.sunken, in: Capsule())
            }
        }
        .padding(8)
    }

    private var vaultList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Vaults").marginFont(MarginTextSize.xs, .semibold).foregroundStyle(MarginColor.textTertiary).padding(.horizontal, 10).padding(.vertical, 6)
            ForEach(workspace.vaults?.recentVaults() ?? []) { v in
                Button { close(); if !v.isCurrent { workspace.vaults?.open(v) } } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(v.name).marginFont(14)
                            Text(v.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).marginFont(MarginTextSize.xs)
                                .foregroundStyle(MarginColor.textTertiary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if v.isCurrent { Icon("check", size: 15, color: MarginColor.accentText) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(MenuRowStyle())
            }
            MarginDivider().padding(.vertical, 6)
            row("Open folder as vault…", icon: "folder_open") { close(); workspace.vaults?.openFolder() }
            row("Create new vault…", icon: "add") { close(); workspace.vaults?.createVault() }
            row("Manage vaults…", icon: "tune") { close(); workspace.dialog = .manageVaults }
        }
        .padding(8)
        .frame(width: 280)
        .background(MarginColor.sunken.opacity(0.5))
    }

    private func settings(_ section: SettingsModel.Section) {
        close()
        workspace.settingsModel().section = section
        workspace.open(.settings)
    }

    private func row(_ title: String, icon: String, meta: String? = nil, shortcut: String? = nil, submenu: Bool = false,
                     active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(icon, size: 17, color: active ? MarginColor.accentText : MarginColor.textSecondary)
                Text(title).marginFont(14).foregroundStyle(active ? MarginColor.accentText : MarginColor.ink)
                Spacer()
                if let meta { Text(meta).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary) }
                if let shortcut { Text(shortcut).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary) }
                if submenu { Icon("chevron_right", size: 14, color: MarginColor.textTertiary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(active ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }
}

/// Hover highlight for popup rows.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration)
    }

    private struct MenuRowBody: View {
        let configuration: Configuration
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .background(hovered && enabled ? MarginColor.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .opacity(enabled ? 1 : 0.45)
                .onHover { hovered = $0 }
        }
    }
}

/// Gallery screen `account`: the popup, closed and with the vault list open.
struct AccountSheet: View {
    @State private var workspace: Workspace = {
        let w = Workspace(env: .fixture())
        w.profile = Profile(name: "Anna Kováčová", school: "Masaryk University")
        return w
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            AccountPopup(close: {}).background(MarginColor.surface, in: RoundedRectangle(cornerRadius: 12)).marginShadow(.modal)
        }
        .environment(workspace)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MarginColor.canvas)
    }
}
