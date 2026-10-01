import MarginCore
import Observation
import SwiftUI

/// Settings (popups 2g Editor, Screens 1g Semesters; M10-21.U, M11-05.U): values live in
/// `SettingsStore` and `SemesterStore`; the editor reads them when a note opens.
@MainActor @Observable
public final class SettingsModel {
    public enum Section: String, CaseIterable, Sendable {
        case general, editor, files, semesters, notifications, hotkeys

        var title: String {
            switch self {
            case .general: "General"
            case .editor: "Editor"
            case .files: "Files and links"
            case .semesters: "Semesters"
            case .notifications: "Notifications"
            case .hotkeys: "Hotkeys"
            }
        }

        var icon: String {
            switch self {
            case .general: "settings"
            case .editor: "edit_note"
            case .files: "folder"
            case .semesters: "school"
            case .notifications: "bell"
            case .hotkeys: "keyboard"
            }
        }
    }

    public var section: Section = .editor
    public var readableLineLength = true
    public var defaultView: EditorViewMode = .editing
    public var showProperties = true
    public var showLineNumbers = false
    public var rewriteLinks = true
    public var reminderMinutes = 10
    public private(set) var semesters: [Semester] = []
    public private(set) var reminderPermission: ReminderPermission = .notDetermined
    private let env: AppEnvironment

    public init(env: AppEnvironment) { self.env = env }

    public func load() async {
        readableLineLength = await env.settings.get(Settings.readableLineLength)
        defaultView = await env.settings.get(Settings.defaultView)
        showProperties = await env.settings.get(Settings.showProperties)
        showLineNumbers = await env.settings.get(Settings.showLineNumbers)
        rewriteLinks = await env.settings.get(Settings.rewriteLinksOnRename)
        reminderMinutes = await env.settings.get(Settings.reminderMinutes)
        semesters = (try? await env.semesters.semesters()) ?? []
        reminderPermission = await env.reminders.permission
    }

    public func save() async throws {
        try await env.settings.set(Settings.readableLineLength, readableLineLength)
        try await env.settings.set(Settings.defaultView, defaultView)
        try await env.settings.set(Settings.showProperties, showProperties)
        try await env.settings.set(Settings.showLineNumbers, showLineNumbers)
        try await env.settings.set(Settings.rewriteLinksOnRename, rewriteLinks)
        try await env.settings.set(Settings.reminderMinutes, reminderMinutes)
    }

    public func update(_ semester: Semester, name: String, start: LocalDate, end: LocalDate, breakWeeks: [Int]) async throws {
        _ = try await env.semesters.update(id: semester.id, SemesterUpdate(name: name, start: start, end: end, breakWeeks: breakWeeks),
                                           actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        await load()
    }

    public func requestReminders() async {
        reminderPermission = (try? await env.reminders.requestPermission()) ?? reminderPermission
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel
    @Environment(Workspace.self) private var workspace

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Options").marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textTertiary)
                    .padding(.horizontal, 10).padding(.bottom, 6)
                ForEach(SettingsModel.Section.allCases, id: \.self) { s in
                    SidebarItemRow(item: .init(s.title, icon: s.icon, isOn: model.section == s) { model.section = s })
                }
                SidebarItemRow(item: .init("Agent", icon: "auto_awesome", meta: "Later version"))
                    .opacity(0.5)
                Spacer()
            }
            .padding(14)
            .frame(width: 220)
            .background(MarginColor.inspector)
            MarginDivider(.vertical)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.section.title).marginFont(MarginTextSize.lg, .semibold).padding(.bottom, 12)
                    content
                }
                .padding(.horizontal, 36).padding(.vertical, 28)
                .frame(maxWidth: 720, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.load() }
        .onChange(of: [model.readableLineLength, model.showProperties, model.showLineNumbers, model.rewriteLinks]) { persist() }
        .onChange(of: model.defaultView) { persist() }
        .onChange(of: model.reminderMinutes) { persist() }
    }

    private func persist() {
        workspace.perform("Save settings") { try await model.save(); workspace.applySettings() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.section {
        case .general:
            row("Vault", "Notes are Markdown files in this folder, readable by Obsidian and any editor.") {
                Text(workspace.vaultURL?.path(percentEncoded: false) ?? "Sample data (not saved to disk)")
                    .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary).lineLimit(2)
            }
            row("Quick capture", "Capture a task or note from any app.") { Text("⌘⇧Space").monospaced() }
        case .editor:
            row("Readable line length", "Limit the width of notes and pages so lines stay easy to read. Turn off to use the full window width.") {
                SwitchView(isOn: $model.readableLineLength, label: "Readable line length")
            }
            row("Default view for new tabs", "Editing shows formatting except on the line you are on.") {
                Picker("", selection: $model.defaultView) {
                    Text("Editing view").tag(EditorViewMode.editing)
                    Text("Reading view").tag(EditorViewMode.reading)
                    Text("Source mode").tag(EditorViewMode.source)
                }
                .labelsHidden().fixedSize()
            }
            row("Show properties", "Show note properties above the title.") { SwitchView(isOn: $model.showProperties, label: "Show properties") }
            row("Show line numbers", "Only in source mode.") { SwitchView(isOn: $model.showLineNumbers, label: "Show line numbers") }
        case .files:
            row("Update links on rename", "When a note or a course folder is renamed, links in other notes follow.") {
                SwitchView(isOn: $model.rewriteLinks, label: "Update links on rename")
            }
        case .semesters:
            ForEach(model.semesters) { s in SemesterEditor(semester: s, model: model) }
            MarginButton("New semester…", icon: "add") { workspace.dialog = .newSemester }
            row("Week starts on", "Used by Today, Upcoming and the timetable.") { Text("Monday") }
            row("Grading scale", "Letter grades from percentages.") { Text("A–F, 93 / 90 / 87…") }
            row("Archive when the semester ends", "Courses become read-only after the last exam.") {
                if let current = workspace.courses.semester {
                    MarginButton("Archive \(current.name)…", size: .small) { workspace.dialog = .archiveSemester(current) }
                }
            }
        case .notifications:
            row("Remind before a class", "A notification with the class note, this many minutes before it starts.") {
                Stepper("\(model.reminderMinutes) min", value: $model.reminderMinutes, in: 0...60, step: 5)
            }
            row("Notifications", model.reminderPermission == .authorized ? "Allowed." : "Margin needs permission to notify you.") {
                if model.reminderPermission != .authorized {
                    MarginButton("Allow…", size: .small) { Task { await model.requestReminders() } }
                }
            }
        case .hotkeys:
            ForEach([("Command palette", "⌘K"), ("Quick capture (anywhere)", "⌘⇧Space"), ("New note", "⌘N"),
                     ("Search", "⌘⇧F"), ("Reading view", "⌘E"), ("Toggle sidebar", "⌥⌘S"),
                     ("Toggle inspector", "⌥⌘I"), ("New tab", "⌘T"), ("Close tab", "⌘W"), ("Settings", "⌘,")], id: \.0) { k in
                row(k.0, nil) { Text(k.1).monospaced().foregroundStyle(MarginColor.textSecondary) }
            }
        }
    }

    private func row<V: View>(_ title: String, _ detail: String?, @ViewBuilder _ value: () -> V) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).marginFont(MarginTextSize.base)
                if let detail { Text(detail).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary).lineSpacing(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            value()
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { MarginDivider(color: MarginColor.hover) }
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
