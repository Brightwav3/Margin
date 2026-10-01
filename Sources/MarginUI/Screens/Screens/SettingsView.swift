import AppKit
import MarginCore
import Observation
import SwiftUI

/// Settings window (Margin Account v3 2a–2l, popups 2g, Screens 1g): an Account group (profile,
/// vault and files, sync, sign-in) above the app options. Values live in `SettingsStore` in the
/// vault's `.margin/settings.json`; nothing is sent anywhere.
@MainActor @Observable
public final class SettingsModel {
    public enum Section: String, CaseIterable, Sendable {
        case profile, vault, sync, signIn
        case general, editor, appearance, shortcuts, semesters, notifications, flashcards, agent, plugins

        static let account: [Section] = [.profile, .vault, .sync, .signIn]
        static let options: [Section] = [.general, .editor, .appearance, .shortcuts, .semesters, .notifications, .flashcards, .agent, .plugins]

        var title: String {
            switch self {
            case .profile: "Profile"
            case .vault: "Vault and files"
            case .sync: "Sync"
            case .signIn: "Sign-in"
            case .general: "General"
            case .editor: "Editor"
            case .appearance: "Appearance"
            case .shortcuts: "Keyboard shortcuts"
            case .semesters: "Semesters"
            case .notifications: "Notifications"
            case .flashcards: "Flashcards"
            case .agent: "Agent"
            case .plugins: "Plugins"
            }
        }

        var icon: String {
            switch self {
            case .profile: "person"
            case .vault: "folder"
            case .sync: "sync"
            case .signIn: "account_circle"
            case .general: "settings"
            case .editor: "edit_note"
            case .appearance: "palette"
            case .shortcuts: "keyboard"
            case .semesters: "school"
            case .notifications: "bell"
            case .flashcards: "style"
            case .agent: "auto_awesome"
            case .plugins: "extension"
            }
        }

        /// Grey note on the right of the sidebar row.
        var meta: String? {
            switch self {
            case .sync: "Off"
            case .signIn: "Optional"
            case .flashcards, .agent, .plugins: "Later"
            default: nil
            }
        }
    }

    public var section: Section = .profile
    // Profile
    public var profile = Profile()
    // Vault and files
    public private(set) var stats: VaultStats?
    public private(set) var snapshots: [NoteVersion] = []
    public private(set) var snapshotTitles: [NoteID: String] = [:]
    public var watchExternal = true
    public var rewriteLinks = true
    // General
    public var openOnStartup: StartupPlace = .courses
    public var confirmBeforeDeleting = true
    public var globalQuickCapture = true
    // Editor
    public var readableLineLength = true
    public var defaultView: EditorViewMode = .editing
    public var showProperties = true
    public var showLineNumbers = false
    public var autoPair = true
    public var smartLists = true
    // Appearance
    public var theme: AppTheme = .system
    public var fontSize = 16.0
    // Notifications
    public var reminderMinutes = 10
    public private(set) var semesters: [Semester] = []
    public private(set) var reminderPermission: ReminderPermission = .notDetermined
    private let env: AppEnvironment

    public init(env: AppEnvironment) { self.env = env }

    public func load() async {
        let s = env.settings
        profile = await s.get(Settings.profile)
        watchExternal = await s.get(Settings.watchExternalChanges)
        rewriteLinks = await s.get(Settings.rewriteLinksOnRename)
        openOnStartup = await s.get(Settings.openOnStartup)
        confirmBeforeDeleting = await s.get(Settings.confirmBeforeDeleting)
        globalQuickCapture = await s.get(Settings.globalQuickCapture)
        readableLineLength = await s.get(Settings.readableLineLength)
        defaultView = await s.get(Settings.defaultView)
        showProperties = await s.get(Settings.showProperties)
        showLineNumbers = await s.get(Settings.showLineNumbers)
        autoPair = await s.get(Settings.autoPair)
        smartLists = await s.get(Settings.smartLists)
        theme = await s.get(Settings.theme)
        fontSize = await s.get(Settings.fontSize)
        reminderMinutes = await s.get(Settings.reminderMinutes)
        semesters = (try? await env.semesters.semesters()) ?? []
        reminderPermission = await env.reminders.permission
        await loadFiles()
    }

    /// Vault sizes and the newest snapshots (Settings › Vault and files › File recovery).
    public func loadFiles() async {
        stats = try? await env.indexStatus.vaultStats()
        snapshots = (try? await env.history.recentVersions(limit: 12)) ?? []
        let notes = (try? await env.notes.notes(course: nil)) ?? []
        snapshotTitles = Dictionary(notes.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
    }

    public func save() async throws {
        let s = env.settings
        try await s.set(Settings.profile, profile)
        try await s.set(Settings.watchExternalChanges, watchExternal)
        try await s.set(Settings.rewriteLinksOnRename, rewriteLinks)
        try await s.set(Settings.openOnStartup, openOnStartup)
        try await s.set(Settings.confirmBeforeDeleting, confirmBeforeDeleting)
        try await s.set(Settings.globalQuickCapture, globalQuickCapture)
        try await s.set(Settings.readableLineLength, readableLineLength)
        try await s.set(Settings.defaultView, defaultView)
        try await s.set(Settings.showProperties, showProperties)
        try await s.set(Settings.showLineNumbers, showLineNumbers)
        try await s.set(Settings.autoPair, autoPair)
        try await s.set(Settings.smartLists, smartLists)
        try await s.set(Settings.theme, theme)
        try await s.set(Settings.fontSize, fontSize)
        try await s.set(Settings.reminderMinutes, reminderMinutes)
    }

    public func update(_ semester: Semester, name: String, start: LocalDate, end: LocalDate, breakWeeks: [Int]) async throws {
        _ = try await env.semesters.update(id: semester.id, SemesterUpdate(name: name, start: start, end: end, breakWeeks: breakWeeks),
                                           actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        await load()
    }

    public func requestReminders() async {
        reminderPermission = (try? await env.reminders.requestPermission()) ?? reminderPermission
    }

    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel
    /// In the settings window: room for the traffic lights above the sidebar, the window's background.
    var inWindow = false
    @Environment(Workspace.self) private var workspace
    @State private var shortcutQuery = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            MarginDivider(.vertical)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.section.title).marginFont(MarginTextSize.lg, .semibold).padding(.bottom, 12)
                    content
                }
                .padding(.horizontal, 36).padding(.top, inWindow ? 44 : 28).padding(.bottom, 28)
                .frame(maxWidth: 720, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MarginColor.surface)
        .ignoresSafeArea()
        .task { await model.load() }
        .onChange(of: [model.readableLineLength, model.showProperties, model.showLineNumbers, model.rewriteLinks,
                       model.watchExternal, model.confirmBeforeDeleting, model.globalQuickCapture, model.autoPair,
                       model.smartLists]) { persist() }
        .onChange(of: model.defaultView) { persist() }
        .onChange(of: model.reminderMinutes) { persist() }
        .onChange(of: model.openOnStartup) { persist() }
        .onChange(of: model.theme) { persist() }
        .onChange(of: model.fontSize) { persist() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Avatar(initials: model.profile.initials, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.profile.name.isEmpty ? "Your profile" : model.profile.name).marginFont(14, .semibold).lineLimit(1)
                    Text("Local profile").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textSecondary)
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 14)
            .padding(.top, inWindow ? 34 : 0)
            group("Account", SettingsModel.Section.account)
            group("Options", SettingsModel.Section.options).padding(.top, 12)
            Spacer()
        }
        .padding(14)
        .frame(width: 230)
        .background(MarginColor.inspector)
    }

    private func group(_ title: String, _ sections: [SettingsModel.Section]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textTertiary)
                .padding(.horizontal, 10).padding(.bottom, 4)
            ForEach(sections, id: \.self) { s in
                SidebarItemRow(item: .init(s.title, icon: s.icon, count: s.meta ?? "", isOn: model.section == s) { model.section = s })
            }
        }
    }

    private func persist() {
        workspace.perform("Save settings") { try await model.save(); workspace.applySettings() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.section {
        case .profile: profile
        case .vault: vault
        case .sync: sync
        case .signIn: signIn
        case .general: general
        case .editor: editor
        case .appearance: appearance
        case .shortcuts: shortcuts
        case .semesters: semesters
        case .notifications: notifications
        case .flashcards: later("Flashcards come with the study tools.", "Cards from `Question :: Answer` lines in your notes, reviewed on a schedule. Settings appear here when the feature is in the app.")
        case .agent: later("The agent is off.", "The in-app agent (a local CLI over the vault, D-023) comes in a later version; until then nothing in your notes leaves this Mac.")
        case .plugins: later("Plugins come later.", "Core features (graph, backlinks, outline) are always on. Community plugins will install into .margin/plugins.")
        }
    }

    // MARK: Account

    @ViewBuilder private var profile: some View {
        HStack(spacing: 16) {
            Avatar(initials: model.profile.initials, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.profile.name.isEmpty ? "No name yet" : model.profile.name).marginFont(MarginTextSize.md, .semibold)
                Text("Saved in this vault. Shown as the author on exported notes.")
                    .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
            }
        }
        .padding(.bottom, 8)
        textRow("Name", "Anna Kováčová", $model.profile.name)
        textRow("School", "Masaryk University", $model.profile.school)
        textRow("Programme", "International Relations, BA", $model.profile.programme)
        row("Year of study", nil) {
            Picker("", selection: $model.profile.yearOfStudy) {
                Text("Not set").tag(0)
                ForEach(1...6, id: \.self) { Text("\($0). year").tag($0) }
            }
            .labelsHidden().fixedSize()
        }
        row("Language", "Used for spell check and dates.") {
            Picker("", selection: $model.profile.language) {
                Text("System").tag("")
                Text("Čeština").tag("cs")
                Text("English").tag("en")
                Text("Slovenčina").tag("sk")
            }
            .labelsHidden().fixedSize()
        }
        row("Time zone", nil) {
            Picker("", selection: $model.profile.timeZone) {
                Text("System (\(TimeZone.current.identifier))").tag("")
                ForEach(["Europe/Prague", "Europe/Bratislava", "Europe/London", "Europe/Berlin", "America/New_York"], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().fixedSize()
        }
        notice("lock", "Your profile is saved in .margin/settings.json inside the vault. Nothing is sent anywhere.")
            .onChange(of: model.profile) { persist() }
    }

    @ViewBuilder private var vault: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Icon("folder", size: 16, color: MarginColor.textSecondary)
                Text(workspace.vaultURL?.path(percentEncoded: false) ?? "Sample data (not saved to disk)")
                    .font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: 8))
            MarginButton("Reveal in Finder", size: .small) { workspace.vaults?.revealVault() }.disabled(workspace.vaults == nil)
            MarginButton("Manage vaults…", size: .small) { workspace.dialog = .manageVaults }.disabled(workspace.vaults == nil)
        }
        .padding(.bottom, 8)
        row("Notes", nil) {
            Text(model.stats.map { "\($0.noteCount) .md files · \(SettingsModel.bytes($0.noteBytes))" } ?? "…")
                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
        }
        row("Attachments", "PDFs, slides and images next to your notes (a course's _files folder).") {
            Text(model.stats.map { "\($0.attachmentCount) files · \(SettingsModel.bytes($0.attachmentBytes))" } ?? "…")
                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
        }
        row("Pick up changes made outside Margin", "Edits from Finder, Git or other apps appear immediately.") {
            SwitchView(isOn: $model.watchExternal, label: "Pick up changes made outside Margin")
        }
        row("Update links on rename", "When a note or a course folder is renamed, links in other notes follow.") {
            SwitchView(isOn: $model.rewriteLinks, label: "Update links on rename")
        }
        Text("File recovery").marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textTertiary).padding(.top, 22)
        row("Snapshots", "Taken when you save (at most every 5 minutes) and close a note; kept for 30 days in .margin/history. "
            + (model.stats.map { SettingsModel.bytes($0.historyBytes) } ?? "")) { EmptyView() }
        if model.snapshots.isEmpty {
            Text("No snapshots yet.").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary).padding(.vertical, 10)
        }
        ForEach(model.snapshots) { v in
            HStack(spacing: 16) {
                Text(snapshotTime(v)).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary).frame(width: 120, alignment: .leading)
                Text(model.snapshotTitles[v.noteID] ?? v.noteID).marginFont(MarginTextSize.sm).lineLimit(1)
                Spacer()
                Text(SettingsModel.bytes(Int64(v.byteCount))).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                Button("Restore") { workspace.dialog = .restoreSnapshot(v) }
                    .buttonStyle(.plain).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.accentText)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { MarginDivider(color: MarginColor.hover) }
        }
    }

    private func snapshotTime(_ v: NoteVersion) -> String {
        let local = workspace.env.clock.localDateTime(from: v.timestamp)
        let today = workspace.env.clock.today
        let day = local.date == today ? "Today" : local.date == today.adding(days: -1) ? "Yesterday" : CourseDetailModel.day(local.date)
        return "\(day), \(local.time.string)"
    }

    @ViewBuilder private var sync: some View {
        notice("laptop_mac", "Sync is off. This vault exists only on this Mac.")
        choice("Off", "Files stay in \(workspace.vaultURL?.lastPathComponent ?? "the vault folder") and nowhere else.", on: true, tag: nil)
        choice("A folder you already sync", "Move the vault into iCloud Drive, Dropbox or a Git repository, then open it with Manage vaults. Margin just reads the folder.",
               on: false, tag: "No account")
        choice("Margin Sync", "End-to-end encrypted sync with version history. Needs an account; not available yet.", on: false, tag: "Optional add-on")
            .opacity(0.55)
    }

    @ViewBuilder private var signIn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not signed in").marginFont(MarginTextSize.md, .semibold)
            Text("An account is only used for Margin Sync and a supporter licence. Notes, settings and plugins stay on this Mac either way.")
                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
            HStack(spacing: 8) {
                MarginButton("Sign in…", kind: .primary, size: .small) {}.disabled(true)
                MarginButton("Create account", size: .small) {}.disabled(true)
                Text("Accounts are not available yet.").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        Text("What needs an account").marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textTertiary).padding(.top, 22)
        row("Margin Sync", nil) { Text("Account + subscription").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary) }
        row("Everything else", nil) { Text("Nothing").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary) }
        Text("Privacy").marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textTertiary).padding(.top, 22)
        row("Check for updates", "Margin does not contact any server.") { SwitchView(isOn: .constant(false), label: "Check for updates").disabled(true) }
        row("Send crash reports", "Off. Note content is never included.") { SwitchView(isOn: .constant(false), label: "Send crash reports").disabled(true) }
    }

    // MARK: Options

    @ViewBuilder private var general: some View {
        row("Open on startup", nil) {
            Picker("", selection: $model.openOnStartup) {
                Text("Courses").tag(StartupPlace.courses)
                Text("Today").tag(StartupPlace.today)
                Text("Upcoming").tag(StartupPlace.upcoming)
                Text("Inbox").tag(StartupPlace.inbox)
            }
            .labelsHidden().fixedSize()
        }
        row("Quick capture from any app", "⇧⌘Space opens a small window over other apps.") {
            SwitchView(isOn: $model.globalQuickCapture, label: "Quick capture from any app")
        }
        row("Confirm before deleting", "Notes and courses go to the Trash either way.") {
            SwitchView(isOn: $model.confirmBeforeDeleting, label: "Confirm before deleting")
        }
        row("Version", "Margin \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9") · updates come as new builds") { EmptyView() }
    }

    @ViewBuilder private var editor: some View {
        row("Default mode", "Live preview formats Markdown as you type. ⇧⌘E for source.") {
            Picker("", selection: $model.defaultView) {
                Text("Live preview").tag(EditorViewMode.editing)
                Text("Reading view").tag(EditorViewMode.reading)
                Text("Source mode").tag(EditorViewMode.source)
            }
            .labelsHidden().fixedSize()
        }
        row("Readable line length", "Limits text width to about 70 characters.") {
            SwitchView(isOn: $model.readableLineLength, label: "Readable line length")
        }
        row("Show properties", "Note properties above the title.") { SwitchView(isOn: $model.showProperties, label: "Show properties") }
        row("Auto-pair brackets", "Typing ( [ { \" or ` adds the closing pair; with a selection, wraps it.") {
            SwitchView(isOn: $model.autoPair, label: "Auto-pair brackets")
        }
        row("Smart lists", "Enter continues a list or task; on an empty item it ends the list.") {
            SwitchView(isOn: $model.smartLists, label: "Smart lists")
        }
    }

    @ViewBuilder private var appearance: some View {
        HStack(spacing: 14) {
            ForEach(AppTheme.allCases, id: \.self) { t in
                Button { model.theme = t } label: {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(t == .dark ? Color(hex: 0x1C1E26) : t == .light ? .white : Color(hex: 0x8D9AB0))
                            .frame(width: 120, height: 76)
                            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(model.theme == t ? MarginColor.accent : MarginColor.borderCard, lineWidth: model.theme == t ? 2 : 1) }
                        Text(t == .system ? "Match system" : t.rawValue.capitalized).marginFont(MarginTextSize.sm)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        row("Note text size", "⌘+ and ⌘− change it for the open window.") {
            Picker("", selection: $model.fontSize) {
                ForEach([13.0, 14, 15, 16, 17, 18, 20], id: \.self) { Text("\(Int($0)) px").tag($0) }
            }
            .labelsHidden().fixedSize()
        }
    }

    @ViewBuilder private var shortcuts: some View {
        HStack(spacing: 8) {
            Icon("search", size: 15, color: MarginColor.textTertiary)
            TextField("Search commands", text: $shortcutQuery).textFieldStyle(.plain).marginFont(MarginTextSize.base)
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 6)
        ForEach(HelpDialog.shortcutRows.filter { shortcutQuery.isEmpty || $0.0.localizedCaseInsensitiveContains(shortcutQuery) }, id: \.0) { k in
            row(k.0, nil) { Text(k.1).monospaced().foregroundStyle(MarginColor.textSecondary) }
        }
    }

    @ViewBuilder private var semesters: some View {
        ForEach(model.semesters) { s in SemesterEditor(semester: s, model: model) }
        MarginButton("New semester…", icon: "add") { workspace.dialog = .newSemester }
        row("Week starts on", "Used by Today, Upcoming and the timetable.") { Text("Monday") }
        row("Grading scale", "Letter grades from percentages.") { Text("A–F, 93 / 90 / 87…") }
        row("Archive when the semester ends", "Courses become read-only.") {
            if let current = workspace.courses.semester {
                MarginButton("Archive \(current.name)…", size: .small) { workspace.dialog = .archiveSemester(current) }
            }
        }
    }

    @ViewBuilder private var notifications: some View {
        row("Remind before a class", "A notification with the class note, this many minutes before it starts.") {
            Stepper("\(model.reminderMinutes) min", value: $model.reminderMinutes, in: 0...60, step: 5)
        }
        row("Notifications", model.reminderPermission == .authorized ? "Allowed." : "Margin needs permission to notify you.") {
            if model.reminderPermission != .authorized {
                MarginButton("Allow…", size: .small) { Task { await model.requestReminders() } }
            }
        }
    }

    // MARK: Building blocks

    private func later(_ title: String, _ text: String) -> some View {
        notice("auto_awesome", title + " " + text)
    }

    private func notice(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 16, color: MarginColor.textSecondary)
            Text(text).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary).lineSpacing(2)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .padding(.vertical, 8)
    }

    private func choice(_ title: String, _ detail: String, on: Bool, tag: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().strokeBorder(on ? MarginColor.accent : MarginColor.borderStrong, lineWidth: on ? 5 : 1.5).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).marginFont(MarginTextSize.base)
                    if let tag { Badge(tag) }
                }
                Text(detail).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(on ? MarginColor.accentSoft.opacity(0.4) : MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(on ? MarginColor.accent : MarginColor.borderCard) }
        .padding(.bottom, 8)
    }

    private func textRow(_ title: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        row(title, nil) {
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).frame(width: 260)
        }
    }

    private func row<V: View>(_ title: String, _ detail: String?, @ViewBuilder _ value: () -> V) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).marginFont(MarginTextSize.base)
                if let detail, !detail.isEmpty { Text(detail).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary).lineSpacing(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            value()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { MarginDivider(color: MarginColor.hover) }
    }
}

/// Round initials on the dark ink colour (rail, account popup, settings).
struct Avatar: View {
    let initials: String
    var size: CGFloat = 30

    var body: some View {
        Text(initials)
            .font(.margin(size * 0.38, .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(MarginColor.ink, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Screens 1g: dates and reading weeks of a semester.
private struct SemesterEditor: View {
    let semester: Semester
    let model: SettingsModel
    @Environment(Workspace.self) private var workspace
    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var breaks = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 200)
                if semester.isArchived { Badge("Archived") }
                if semester.id == workspace.courses.semester?.id { Badge("Current", tone: .accent) }
                Spacer()
            }
            HStack(spacing: 12) {
                DatePicker("Starts", selection: $start, displayedComponents: .date)
                DatePicker("Ends", selection: $end, displayedComponents: .date)
            }
            HStack {
                Text("Reading weeks (no sessions)").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                TextField("e.g. 7", text: $breaks).textFieldStyle(.roundedBorder).frame(width: 120)
                Spacer()
                MarginButton("Save dates", size: .small) { save() }
            }
        }
        .marginFont(MarginTextSize.base)
        .padding(14)
        .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .padding(.bottom, 12)
        .onAppear {
            name = semester.name
            breaks = semester.breakWeeks.map(String.init).joined(separator: ", ")
            let clock = workspace.env.clock
            if let s = clock.date(from: LocalDateTime(date: semester.start, time: LocalTime(hour: 12, minute: 0)!)) { start = s }
            if let e = clock.date(from: LocalDateTime(date: semester.end, time: LocalTime(hour: 12, minute: 0)!)) { end = e }
        }
    }

    private func save() {
        let clock = workspace.env.clock
        let weeks = breaks.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) }
        workspace.perform("Save semester") {
            try await model.update(semester, name: name, start: clock.localDateTime(from: start).date,
                                   end: clock.localDateTime(from: end).date, breakWeeks: weeks)
            await workspace.refreshAfterWrite()
            workspace.show("Saved \(name)")
        }
    }
}
