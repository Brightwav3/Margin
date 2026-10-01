import MarginCore
import SwiftUI

/// Left panel inside the content card. Without a Notes space it is 220 px; with one it is
/// 280 px and slides between Navigation and Notes (420 ms, `cubic-bezier(.2,.8,.2,1)`).
struct SidebarPanel: View {
    @Bindable var model: AppModel
    let content: SidebarContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Default 220 px, 280 px with a Notes space (mockup); the user can drag it wider or narrower.
    var width: CGFloat { Self.width(model: model, content: content) }

    static func width(model: AppModel, content: SidebarContent) -> CGFloat {
        model.sidebarWidth ?? (content.notes == nil ? 220 : 280)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    NavigationPage(content: content)
                        .frame(width: geo.size.width)
                    if let notes = content.notes {
                        NotesPage(notes: notes) { go(.navigation) }
                            .frame(width: geo.size.width)
                    }
                }
                .offset(x: content.notes == nil ? 0 : -CGFloat(model.sidebarPage.rawValue) * geo.size.width)
            }
            .clipped()
            // Lists scroll clear of the floating space dots.
            .safeAreaPadding(.bottom, content.notes == nil ? 0 : 34)
        }
        .overlay(alignment: .bottom) {
            if let notes = content.notes {
                SpaceSwitcher(page: model.sidebarPage, title: content.title, notes: notes) { go($0) }
                    .modifier(CourseContextMenu(courseID: content.courseID))
                    .padding(.bottom, 12)
            }
        }
        .frame(width: width)
        .overlay(alignment: .trailing) { MarginDivider(.vertical) }
        .overlay(alignment: .trailing) {
            ResizeHandle(edge: .trailing, width: width,
                         onChange: { model.setSidebarWidth($0) },
                         onReset: { model.setSidebarWidth(nil) })
        }
        .overlay {
            if content.notes != nil {
                HorizontalSwipe { step in
                    let next = SidebarPage(rawValue: model.sidebarPage.rawValue + step) ?? model.sidebarPage
                    if next != model.sidebarPage { go(next) }
                }
            }
        }
    }

    private func go(_ page: SidebarPage) {
        withAnimation(Shell.slideAnimation(reduceMotion)) { model.sidebarPage = page }
    }
}

private struct NavigationPage: View {
    let content: SidebarContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let dot = content.dot {
                    Circle().fill(Color(hexString: dot)).frame(width: 10, height: 10)
                }
                SidebarTitle(title: content.title, views: content.views)
                    .modifier(CourseContextMenu(courseID: content.courseID))
                Spacer(minLength: 0)
                Icon("search", size: 20, color: MarginColor.textSecondary)
            }
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))

            HStack(spacing: 4) {
                SidebarActionButton(title: content.actionTitle, icon: content.actionIcon, key: content.actionKey,
                                    action: content.onAction)
                if let course = content.courseID { NewNoteMenu(courseID: course) }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(content.sections) { section in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.label)
                                .marginFont(MarginTextSize.sm)
                                .foregroundStyle(MarginColor.textTertiary)
                                .padding(EdgeInsets(top: 16, leading: 10, bottom: 6, trailing: 10))
                            ForEach(section.items) { SidebarItemRow(item: $0) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .contextMenu { SidebarBackgroundMenu() }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
    }
}

/// 1n: right-click on empty space in the sidebar.
private struct SidebarBackgroundMenu: View {
    @Environment(Workspace.self) private var workspace: Workspace?

    var body: some View {
        if let workspace {
            MenuItem("New note", "edit_square") { workspace.run(command: "new-note") }.keyboardShortcut("n")
            MenuItem("New folder", "create_new_folder") {}.disabled(true)
            MenuItem("New course…", "school") { workspace.dialog = .newCourse }
            Divider()
            MenuItem("Import syllabus…", "upload_file") { workspace.run(command: "syllabus") }
                .disabled(workspace.courses.cards.isEmpty)
            MenuItem("Import Markdown files…", "drive_folder_upload") { workspace.importMarkdownFiles() }
                .disabled(workspace.courses.cards.isEmpty)
            Divider()
            Menu {
                ForEach(CourseListQuery.SortKey.allCases, id: \.self) { key in
                    Button { workspace.courses.sort = key } label: {
                        if workspace.courses.sort == key { Label(key.menuTitle, systemImage: "checkmark") } else { Text(key.menuTitle) }
                    }
                }
            } label: { Label { Text("Sort courses") } icon: { MenuIcons.image("sort") } }
            Divider()
            MenuItem("Show archived semesters", "inventory_2") { workspace.open(.archive) }
        }
    }
}

extension CourseListQuery.SortKey {
    var menuTitle: String {
        switch self {
        case .name: "Name"
        case .code: "Code"
        case .nextSession: "Next class"
        case .dueCount: "Open tasks"
        }
    }
}

/// Panel title with its chevron; with `views` the chevron opens a menu of them.
private struct SidebarTitle: View {
    let title: String
    let views: [SidebarContent.Item]

    var body: some View {
        if views.isEmpty {
            label
        } else {
            Menu {
                ForEach(views) { view in
                    Button {
                        view.action?()
                    } label: {
                        if view.isOn { Label(view.title, systemImage: "checkmark") } else { Text(view.title) }
                    }
                }
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            Text(title)
                .marginFont(MarginTextSize.base, .semibold)
                .foregroundStyle(MarginColor.ink)
                .lineLimit(1)
            Icon("expand_more", size: 16, color: MarginColor.textSecondary)
        }
        .contentShape(Rectangle())
    }
}

private struct SidebarActionButton: View {
    let title: String
    let icon: String
    let key: String
    let action: (@MainActor @Sendable () -> Void)?
    @State private var hovered = false

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 10) {
                Icon(icon, size: 18, color: MarginColor.ink)
                Text(title).marginFont(14).foregroundStyle(MarginColor.ink)
                Spacer(minLength: 0)
                Text(key).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(hovered ? MarginColor.borderSubtle : MarginColor.hover, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct SidebarItemRow: View {
    let item: SidebarContent.Item
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon = item.icon {
                Icon(icon, size: 17, color: item.isOn ? MarginColor.accent : MarginColor.textSecondary)
            }
            if let dot = item.dot {
                Circle().fill(Color(hexString: dot)).frame(width: 7, height: 7).padding(.horizontal, 5)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).marginFont(14).lineLimit(1)
                if let meta = item.meta {
                    Text(meta).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.count).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
        }
        .foregroundStyle(item.isOn ? MarginColor.accentText : MarginColor.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 32)
        .background(item.isOn ? MarginColor.accentSoft : (hovered ? MarginColor.hover : .clear),
                    in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        .contentShape(RoundedRectangle(cornerRadius: MarginRadius.sm))
        .onHover { hovered = $0 }
        .onTapGesture { item.action?() }
        .modifier(CourseContextMenu(courseID: item.courseID))
        .modifier(FullTitleTooltip(title: item.title, detail: item.meta, isLong: item.title.count > 24))
        .accessibilityAddTraits(item.action == nil ? [] : .isButton)
    }
}

private struct NotesPage: View {
    let notes: NotesSpace
    let onBack: () -> Void
    @State private var filter = "All"
    @Environment(Workspace.self) private var workspace: Workspace?

    /// 1b: New note, Sort notes ▸.
    @ViewBuilder private var notesMenu: some View {
        MenuItem("New note", "edit_square") { notes.onNew?() }
        MenuItem("New folder", "create_new_folder") {}.disabled(true)
        Divider()
        if let workspace {
            Menu {
                Section("Sort by") {
                    sortButton("Date (newest first)", .newest, workspace)
                    sortButton("Date (oldest first)", .oldest, workspace)
                    sortButton("Name", .name, workspace)
                }
            } label: { Label { Text("Sort notes") } icon: { MenuIcons.image("sort") } }
        }
    }

    private func sortButton(_ title: String, _ sort: Workspace.NotesSort, _ workspace: Workspace) -> some View {
        Button { workspace.notesSort = sort } label: {
            if workspace.notesSort == sort { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Icon("arrow_back", size: 18)
                    Circle().fill(Color(hexString: notes.courseStyle.dot)).frame(width: 7, height: 7)
                    Text(notes.courseName).marginFont(14)
                }
                .foregroundStyle(MarginColor.textSecondary)
                .padding(.horizontal, 6)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Icon("description", size: 18, color: MarginColor.ink)
                Text("Notes").marginFont(MarginTextSize.md, .semibold)
                    .contextMenu { notesMenu }
                Spacer(minLength: 0)
                Button { notes.onNew?() } label: {
                    Icon("add", size: 20, color: MarginColor.textSecondary).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New note")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            HStack(spacing: 8) {
                Icon("search", size: 18)
                Text("Search notes…").frame(maxWidth: .infinity, alignment: .leading)
                Text("⌘K").marginFont(MarginTextSize.xs)
            }
            .marginFont(MarginTextSize.base)
            .foregroundStyle(MarginColor.textTertiary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            // Liquid Glass (macOS 27 SDK): reacts to hover and press, capsule like system search.
            .glassEffect(.regular.interactive(), in: Capsule())

            HStack(spacing: 4) {
                ForEach(["All", "Lectures", "Tasks"], id: \.self) { name in
                    FilterChip(name, isOn: filter == name, style: .compact) { filter = name }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(notes.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .marginFont(MarginTextSize.sm, .semibold)
                                .foregroundStyle(MarginColor.textSecondary)
                                .padding(EdgeInsets(top: 4, leading: 6, bottom: 6, trailing: 6))
                            ForEach(group.notes) { NoteRow(note: $0) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .foregroundStyle(MarginColor.ink)
    }
}

private struct NoteRow: View {
    let note: NotesSpace.Note
    @State private var hovered = false
    @Environment(Workspace.self) private var workspace: Workspace?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(note.title).marginFont(MarginTextSize.base, .semibold).lineLimit(1)
                Spacer(minLength: 0)
                Text(note.time).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
            }
            Text(note.snippet)
                .marginFont(MarginTextSize.sm)
                .foregroundStyle(MarginColor.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(note.isSelected ? MarginColor.accentSoft : (hovered ? MarginColor.hover : .clear),
                    in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        .contentShape(RoundedRectangle(cornerRadius: MarginRadius.sm))
        .onHover { hovered = $0 }
        .onTapGesture { note.action?() }
        .contextMenu {
            if let workspace, let summary = note.summary { NoteMenuItems(note: summary).environment(workspace) }
        }
        .modifier(FullTitleTooltip(title: note.title, detail: nil, isLong: note.title.count > 26))
    }
}

/// 3c: long titles in narrow lists show the full title (and their meta) on hover.
struct FullTitleTooltip: ViewModifier {
    let title: String
    let detail: String?
    let isLong: Bool

    func body(content: Content) -> some View {
        if isLong { content.marginTooltip(title, detail: detail, placement: .trailing) } else { content }
    }
}

/// Two small dots floating at the bottom of the sidebar: the current place and Notes.
private struct SpaceSwitcher: View {
    let page: SidebarPage
    let title: String
    let notes: NotesSpace
    let go: (SidebarPage) -> Void

    var body: some View {
        // Liquid Glass (macOS 27 SDK): the dots share one container so their glass blends.
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                dot(.navigation, icon: notes.courseStyle.icon,
                    bg: Color(hexString: notes.courseStyle.background),
                    fg: Color(hexString: notes.courseStyle.foreground), name: title)
                dot(.notes, icon: "description", bg: MarginColor.accentSoft, fg: MarginColor.accentText,
                    name: "Notes")
            }
        }
    }

    private func dot(_ target: SidebarPage, icon: String, bg: Color, fg: Color, name: String) -> some View {
        let on = page == target
        return Button { go(target) } label: {
            Icon(icon, size: 13, weight: on ? .bold : .regular, color: on ? fg : MarginColor.textTertiary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // The active space is tinted with its colour; the other is clear glass.
        .glassEffect(on ? .regular.tint(bg).interactive() : .regular.interactive(), in: Circle())
        .help(name)
        .animation(.easeOut(duration: 0.2), value: on)
    }
}


/// 2f: the split part of „New lecture note“: which kind of note to create.
private struct NewNoteMenu: View {
    let courseID: String
    @Environment(Workspace.self) private var workspace: Workspace?

    var body: some View {
        Menu {
            if let workspace {
                let m = workspace.courseModel(courseID)
                MenuItem("Lecture note", "school") { workspace.newLectureNote() }
                MenuItem("Blank note", "note") { workspace.newNote(in: m) }.keyboardShortcut("n")
                MenuItem("Study note", "menu_book") { workspace.newNote(in: m, title: "Study note", kind: .study) }
                MenuItem("Lab report", "science") {
                    workspace.newNote(in: m, title: "Lab report", kind: .lab,
                                      body: "## Aim\n\n## Method\n\n## Results\n\n## Discussion\n")
                }
                MenuItem("Seminar note", "groups") {
                    workspace.newNote(in: m, title: "Seminar", kind: .seminar, body: "## Readings\n\n## Discussion\n\n## Questions\n")
                }
                Divider()
                MenuItem("From template…", "dashboard_customize") {}.disabled(true)
                MenuItem("Quick capture", "bolt") { workspace.capture.open() }
            }
        } label: {
            Icon("expand_more", size: 16, color: MarginColor.textSecondary)
                .frame(width: 30, height: 34)
                .background(MarginColor.hover, in: RoundedRectangle(cornerRadius: 10))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .marginTooltip("More kinds of notes")
    }
}
