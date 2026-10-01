import MarginCore
import SwiftUI

/// 3a Manage vaults: recent vaults, create a new one, open any folder (Margin Account v3).
struct ManageVaultsDialog: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        let vaults = workspace.vaults?.recentVaults() ?? []
        DialogCard(title: "Manage vaults", icon: "folder", width: 560) {
            VStack(alignment: .leading, spacing: 4) {
                FieldLabel(text: "Recent")
                ForEach(vaults) { v in
                    HStack(spacing: 12) {
                        Text(String(v.name.prefix(1)).uppercased())
                            .font(.margin(14, .semibold)).foregroundStyle(MarginColor.accentText)
                            .frame(width: 32, height: 32)
                            .background(MarginColor.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(v.name).marginFont(MarginTextSize.base, .medium)
                            Text(v.path).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if v.isCurrent {
                            Badge("Open", tone: .accent)
                        } else {
                            MarginButton("Open", size: .small) { workspace.dialog = nil; workspace.vaults?.open(v) }
                            Button { workspace.dialog = .removeVault(v) } label: { Icon("close", size: 14, color: MarginColor.textTertiary) }
                                .buttonStyle(.plain).marginTooltip("Remove from list").accessibilityLabel("Remove \(v.name) from list")
                        }
                    }
                    .padding(.vertical, 6)
                }
                if vaults.isEmpty {
                    Text("No vaults yet.").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                }
            }
            MarginDivider()
            action("Create new vault", "A new folder on this Mac.", button: "Create") { workspace.dialog = nil; workspace.vaults?.createVault() }
            action("Open folder as vault", "Any folder of Markdown files, also one in iCloud Drive or Dropbox.", button: "Open") {
                workspace.dialog = nil; workspace.vaults?.openFolder()
            }
            action("Open from Margin Sync", "Needs an account; not available yet.", button: "Sign in", enabled: false) {}
        } footer: {
            MarginButton("Done", kind: .primary) { workspace.dialog = nil }.keyboardShortcut(.defaultAction)
        }
    }

    private func action(_ title: String, _ detail: String, button: String, enabled: Bool = true, _ run: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).marginFont(MarginTextSize.base)
                Text(detail).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
            }
            Spacer()
            MarginButton(button, size: .small, action: run).disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.55)
    }
}

/// 3b Remove from list: the folder stays on disk.
struct RemoveVaultDialog: View {
    let vault: VaultChoice
    @Environment(Workspace.self) private var workspace

    var body: some View {
        DialogCard(title: "Remove “\(vault.name)” from the list?", width: 460) {
            Text("The folder and its files stay on disk. You can open it again any time with Open folder as vault.")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
            Text(vault.path).font(.system(size: 12, design: .monospaced)).foregroundStyle(MarginColor.textSecondary)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: 8))
        } footer: {
            MarginButton("Cancel") { workspace.dialog = .manageVaults }
            MarginButton("Remove", kind: .primary) {
                workspace.vaults?.removeFromList(vault)
                workspace.dialog = .manageVaults
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// 3c Restore snapshot: the diff against now, then the old text as a new save (nothing is lost).
struct RestoreSnapshotDialog: View {
    let version: NoteVersion
    @Environment(Workspace.self) private var workspace
    @State private var title = ""
    @State private var diff: NoteDiff?

    var body: some View {
        DialogCard(title: "Restore “\(title)”?", icon: "history", width: 560) {
            Text("The note goes back to how it was \(when). The current version is saved as a snapshot first, so nothing is lost.")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((diff?.lines ?? []).filter { $0.kind != .equal }.prefix(40).enumerated()), id: \.offset) { _, line in
                        // From the snapshot to now: what is removed now comes back.
                        Text((line.kind == .removed ? "+ " : "− ") + line.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(line.kind == .removed ? MarginColor.successText : MarginColor.dangerText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 1)
                    }
                    if diff?.lines.allSatisfy({ $0.kind == .equal }) == true {
                        Text("Same as now.").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary).padding(10)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 220)
            .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: 8))
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Restore", kind: .primary) { restore() }.keyboardShortcut(.defaultAction)
        }
        .task {
            title = (try? await workspace.env.notes.open(id: version.noteID).summary.title) ?? version.noteID
            diff = try? await workspace.env.history.diffWithCurrent(version)
        }
    }

    private var when: String {
        let local = workspace.env.clock.localDateTime(from: version.timestamp)
        let day = local.date == workspace.env.clock.today ? "today" : CourseDetailModel.day(local.date)
        return "\(day) at \(local.time.string)"
    }

    private func restore() {
        workspace.perform("Restore snapshot") {
            _ = try? await workspace.env.history.snapshot(note: version.noteID, reason: .save)
            _ = try await workspace.env.history.restore(version, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            workspace.dialog = nil
            workspace.show("Restored \(title) from \(when)", icon: "history")
            await workspace.reloadEditor(version.noteID)
        }
    }
}
