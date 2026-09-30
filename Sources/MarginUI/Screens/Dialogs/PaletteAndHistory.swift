import MarginCore
import SwiftUI

/// 1a Command palette (⌘K): notes by full-text search, then commands; ⌘⏎ creates a note.
struct CommandPalette: View {
    @Environment(Workspace.self) private var workspace
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var commands: [RankedCommand] {
        workspace.commands.search(query, limit: 6)
    }

    private var rows: Int { hits.count + commands.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Icon("search", size: 20, color: MarginColor.textSecondary)
                TextField("Search notes and commands", text: $query)
                    .textFieldStyle(.plain).marginFont(17).focused($focused)
                    .accessibilityIdentifier("palette-field")
                    .onSubmit { run(selection) }
                Text("esc").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 16).frame(height: 52)
            MarginDivider(color: Color(hex: 0xEDEEF1))
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if !hits.isEmpty { PopupSection(title: "Notes") }
                    ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                        Button { run(i) } label: {
                            HStack(spacing: 10) {
                                Icon("description", size: 16, color: MarginColor.textSecondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.title).marginFont(MarginTextSize.base).lineLimit(1)
                                    Text(detail(hit)).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary).lineLimit(1)
                                }
                                Spacer()
                                if i == selection { Text("↵").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary) }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(i == selection ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    PopupSection(title: "Commands")
                    if !query.isEmpty {
                        MenuRow(title: "Create note “\(query)”", icon: "edit_square", shortcut: "⌘↵") { create() }
                    }
                    ForEach(Array(commands.enumerated()), id: \.element.id) { j, ranked in
                        let i = hits.count + j
                        MenuRow(title: ranked.command.title, icon: "bolt", shortcut: ranked.command.shortcut ?? "") { run(i) }
                            .background(i == selection ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 600)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .marginShadow(.modal)
        .onAppear { focused = true }
        .onChange(of: query, initial: true) { _, q in
            selection = 0
            Task { @MainActor in
                let found = q.isEmpty ? [] : ((try? await workspace.env.search.search(query: q, filter: SearchFilter(limit: 8))) ?? [])
                if q == query { hits = found }
            }
        }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, rows - 1)); return .handled }
        .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
        .background {
            Button("Create") { create() }.keyboardShortcut(.return, modifiers: .command).opacity(0)
        }
    }

    private func detail(_ hit: SearchHit) -> String {
        let course = hit.courseID.flatMap { workspace.courses.course(id: $0)?.name }
        return [course, hit.snippet.isEmpty ? nil : hit.snippet].compactMap { $0 }.joined(separator: " · ")
    }

    private func run(_ index: Int) {
        if hits.indices.contains(index) {
            let hit = hits[index]
            workspace.dialog = nil
            workspace.open(.note(hit.id), title: hit.title)
            return
        }
        let j = index - hits.count
        if commands.indices.contains(j) {
            workspace.dialog = nil
            workspace.run(command: commands[j].command.id)
        } else if !query.isEmpty {
            workspace.dialog = nil
            workspace.open(.search(query))
        }
    }

    private func create() {
        guard !query.isEmpty else { return }
        let title = query
        workspace.dialog = nil
        workspace.openLink(title, from: workspace.currentCourse)
    }
}

/// Screens 2e Version history: snapshots of the note, diff against now, restore (never deletes).
struct HistoryDialog: View {
    let noteID: NoteID
    @Environment(Workspace.self) private var workspace
    @State private var versions: [NoteVersion] = []
    @State private var selected: NoteVersion?
    @State private var diff: NoteDiff?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Version history").marginFont(MarginTextSize.md, .semibold)
                Spacer()
                Button { workspace.dialog = nil } label: { Icon("close", size: 18, color: MarginColor.textSecondary) }.buttonStyle(.plain)
            }
            .padding(18)
            MarginDivider()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if versions.isEmpty {
                            Text("No earlier versions yet. Margin keeps a snapshot when a note is saved.")
                                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary).padding(12)
                        }
                        ForEach(versions) { v in
                            let on = v.id == selected?.id
                            Button { choose(v) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(time(v)).marginFont(14, on ? .semibold : .regular)
                                        .foregroundStyle(on ? MarginColor.accentText : MarginColor.ink)
                                    Text("\(v.byteCount) bytes").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(on ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 220)
                MarginDivider(.vertical)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array((diff?.lines ?? []).enumerated()), id: \.offset) { _, line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: 13, design: .monospaced))
                                .strikethrough(line.kind == .removed)
                                .foregroundStyle(line.kind == .removed ? MarginColor.dangerText : line.kind == .added ? MarginColor.successText : MarginColor.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 1)
                                .background(line.kind == .removed ? MarginColor.dueSoft : line.kind == .added ? MarginColor.successSoft : .clear)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .frame(height: 420)
            MarginDivider()
            HStack {
                if let diff { Text("+\(diff.addedCount) −\(diff.removedCount) against now").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary) }
                Spacer()
                MarginButton("Cancel") { workspace.dialog = nil }
                MarginButton("Restore this version", kind: .primary) { restore() }.disabled(selected == nil)
            }
            .padding(16)
        }
        .frame(width: 760)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.dialog))
        .marginShadow(.modal)
        .task {
            versions = ((try? await workspace.env.history.versions(note: noteID)) ?? []).sorted { $0.timestamp > $1.timestamp }
            if let first = versions.first { choose(first) }
        }
    }

    private func time(_ v: NoteVersion) -> String {
        let local = workspace.env.clock.localDateTime(from: v.timestamp)
        return "\(CourseDetailModel.day(local.date)) \(CoursesFormat.hour(local.time))"
    }

    private func choose(_ v: NoteVersion) {
        selected = v
        Task { @MainActor in diff = try? await workspace.env.history.diffWithCurrent(v) }
    }

    private func restore() {
        guard let v = selected else { return }
        workspace.perform("Restore version") {
            // The current text is snapshotted first, so restoring never loses anything.
            _ = try? await workspace.env.history.snapshot(note: noteID, reason: .save)
            _ = try await workspace.env.history.restore(v, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            workspace.dialog = nil
            workspace.show("Restored the version of \(time(v))", icon: "history")
            await workspace.reloadEditor(noteID)
        }
    }
}
