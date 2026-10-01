import AppKit
import MarginCore
import SwiftUI
import UniformTypeIdentifiers

/// Modal dialogs over the window (margin-popups 1g, 1h, 2c, 2d, 2e, 3a, 3b, 3c; Screens 2e).
struct DialogHost: View {
    @Environment(Workspace.self) private var workspace
    /// The settings window shows the dialogs opened from it; the main window all others.
    var inSettings = false

    private var mine: Bool {
        let settingsKey = SettingsWindow.shared.isKey
        return inSettings ? settingsKey : !settingsKey
    }

    var body: some View {
        if let dialog = workspace.dialog, mine {
            ZStack {
                Color(hex: 0x1C1E26, opacity: 0.32).ignoresSafeArea().onTapGesture { workspace.dialog = nil }
                Group {
                    switch dialog {
                    case .newCourse: NewCourseDialog()
                    case .deleteNote(let n): DeleteNoteDialog(note: n)
                    case .moveNote(let n): MoveNoteDialog(notes: [n])
                    case .moveNotes(let n): MoveNoteDialog(notes: n)
                    case .deleteNotes(let n): DeleteNotesDialog(notes: n)
                    case .mergeNotes(let n): MergeNotesDialog(notes: n)
                    case .tagNotes(let n): AddTagDialog(notes: n)
                    case .grade(let c): GradeDialog(courseID: c)
                    case .syllabus(let c): SyllabusDialog(courseID: c)
                    case .share(let n): ShareDialog(note: n)
                    case .archiveSemester(let s): ArchiveSemesterDialog(semester: s)
                    case .session(let o): SessionDialog(occurrence: o)
                    case .history(let n): HistoryDialog(noteID: n)
                    case .palette: CommandPalette()
                    case .renameCourse(let c): RenameCourseDialog(course: c)
                    case .courseStyle(let c): CourseStyleDialog(course: c)
                    case .courseSettings(let c): CourseSettingsDialog(course: c)
                    case .deleteCourse(let c): DeleteCourseDialog(course: c)
                    case .newSemester: NewSemesterDialog()
                    case .manageVaults: ManageVaultsDialog()
                    case .renameNote(let n): RenameNoteDialog(note: n)
                    case .renameTag(let t): TagDialog(tag: t, deleting: false)
                    case .deleteTag(let t): TagDialog(tag: t, deleting: true)
                    case .removeVault(let v): RemoveVaultDialog(vault: v)
                    case .restoreSnapshot(let v): RestoreSnapshotDialog(version: v)
                    case .help(let t): HelpDialog(topic: t)
                    }
                }
                .onExitCommand { workspace.dialog = nil }
            }
            .transition(.opacity)
        }
    }
}

/// White dialog card: radius 16, modal shadow, title row with close.
struct DialogCard<Content: View, Footer: View>: View {
    let title: String
    var icon: String?
    var width: CGFloat = 480
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @Environment(Workspace.self) private var workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                if let icon { Icon(icon, size: 20, color: MarginColor.textSecondary) }
                Text(title).marginFont(MarginTextSize.md, .semibold)
                Spacer()
                Button { workspace.dialog = nil } label: { Icon("close", size: 18, color: MarginColor.textSecondary) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            content
            HStack(spacing: 10) { Spacer(); footer }
        }
        .padding(22)
        .frame(width: width, alignment: .leading)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.dialog))
        .marginShadow(.modal)
    }
}

/// Label above a field.
struct FieldLabel: View {
    let text: String
    var body: some View { Text(text).marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textSecondary) }
}

struct MarginField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .marginFont(MarginTextSize.base)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
            .overlay { RoundedRectangle(cornerRadius: MarginRadius.sm).strokeBorder(MarginColor.border) }
    }
}

// MARK: 1g New course

struct NewCourseDialog: View {
    @Environment(Workspace.self) private var workspace
    @State private var name = ""
    @State private var code = ""
    @State private var lecturer = ""
    @State private var room = ""
    @State private var faculty = ""
    @State private var color: String?
    @State private var icon: String?
    @State private var sessions: [NewSession] = []
    @State private var saving = false
    @State private var semesterID: SemesterID?

    private var suggestion: CourseIconSuggester.Suggestion {
        CourseIconSuggester.suggest(name: name.isEmpty ? "Course" : name,
                                    usedKeys: Set(workspace.courses.cards.map(\.course.style.color)))
    }
    private var chosenColor: String {
        color ?? CoursePalette.orderedKeys.first { k in !workspace.courses.cards.contains { $0.course.style.color == k } } ?? CoursePalette.orderedKeys.first ?? "bio"
    }
    private var style: CourseStyle { CoursePalette.style(icon: icon ?? suggestion.icon, color: chosenColor) }

    var body: some View {
        DialogCard(title: "New course", width: 520) {
            HStack(spacing: 14) {
                CourseTile(style: style, size: 52)
                TextField("Course name", text: $name)
                    .textFieldStyle(.plain).marginFont(MarginTextSize.lg, .semibold)
            }
            CourseStylePicker(courseName: name,
                              color: Binding(get: { chosenColor }, set: { color = $0 }),
                              icon: Binding(get: { icon ?? suggestion.icon }, set: { icon = $0 }),
                              usedKeys: Set(workspace.courses.cards.map(\.course.style.color)))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) { FieldLabel(text: "Code"); MarginField(placeholder: "PHIL 214", text: $code) }
                VStack(alignment: .leading, spacing: 6) { FieldLabel(text: "Lecturer"); MarginField(placeholder: "Optional", text: $lecturer) }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) { FieldLabel(text: "Room"); MarginField(placeholder: "Optional", text: $room) }
                VStack(alignment: .leading, spacing: 6) { FieldLabel(text: "Faculty"); MarginField(placeholder: "Sciences, Humanities…", text: $faculty) }
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Semester")
                SemesterSelect(semesters: workspace.courses.semesters, current: workspace.courses.semester?.id,
                               selection: Binding(get: { semesterID ?? workspace.courses.semester?.id }, set: { semesterID = $0 }))
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Sessions")
                ForEach(sessions.indices, id: \.self) { i in SessionEditorRow(session: $sessions[i]) { sessions.remove(at: i) } }
                Button {
                    sessions.append(NewSession(day: .monday, start: LocalTime(hour: 10, minute: 0)!, room: room.isEmpty ? nil : room))
                } label: {
                    HStack(spacing: 6) { Icon("add", size: 16); Text("Add session") }
                        .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.accentText)
                }
                .buttonStyle(.plain)
            }
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Create course", kind: .primary) { create() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving || chosenSemester == nil)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var chosenSemester: Semester? {
        let id = semesterID ?? workspace.courses.semester?.id
        return workspace.courses.semesters.first { $0.id == id && !$0.isArchived }
    }

    private func create() {
        guard let semester = chosenSemester else { return }
        saving = true
        let course = NewCourse(name: name.trimmingCharacters(in: .whitespaces), semester: semester.id,
                               code: code, professor: lecturer.isEmpty ? nil : lecturer, room: room.isEmpty ? nil : room,
                               faculty: faculty.isEmpty ? nil : faculty, icon: icon ?? suggestion.icon, color: chosenColor,
                               sessions: sessions)
        workspace.perform("Create course") {
            _ = try await workspace.env.courseWriter.create(course, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            workspace.dialog = nil
            await workspace.courses.load()
            workspace.show("Created \(course.name)")
            if let c = workspace.courses.cards.first(where: { $0.course.name == course.name })?.course { workspace.open(course: c) }
        }
    }
}

struct SessionEditorRow: View {
    @Binding var session: NewSession
    let remove: () -> Void

    /// Usual class lengths (45, 60, 90, 100 minutes …) plus the session's own.
    static func lengths(including current: Double) -> [Double] {
        let usual = [0.75, 1, 1.5, 1.67, 2, 2.5, 3, 3.67, 4]
        return usual.contains(where: { abs($0 - current) < 0.01 }) ? usual : (usual + [current]).sorted()
    }

    static func lengthLabel(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min"
    }

    var body: some View {
        HStack(spacing: 8) {
            Icon("event_repeat", size: 16, color: MarginColor.textSecondary)
            Picker("", selection: $session.day) {
                ForEach(Weekday.allCases, id: \.self) { Text(CoursesFormat.weekday($0)).tag($0) }
            }
            .labelsHidden().frame(width: 72)
            TextField("10:00", text: Binding(get: { session.start.string },
                                              set: { if let t = LocalTime(string: $0) { session.start = t } }))
                .textFieldStyle(.roundedBorder).frame(width: 60)
            Picker("", selection: $session.lengthHours) {
                ForEach(Self.lengths(including: session.lengthHours), id: \.self) { Text(Self.lengthLabel($0)).tag($0) }
            }
            .labelsHidden().frame(width: 84)
            HStack(spacing: 2) {
                TextField("Lecture", text: $session.kind).textFieldStyle(.roundedBorder).frame(width: 92)
                Menu {
                    ForEach(["Lecture", "Seminar", "Lab", "Tutorial", "Přednáška", "Seminář", "Cvičení"], id: \.self) { k in
                        Button(k) { session.kind = k }
                    }
                } label: { Icon("expand_more", size: 14, color: MarginColor.textSecondary) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            TextField("Room", text: Binding(get: { session.room ?? "" }, set: { session.room = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
            Button(action: remove) { Icon("close", size: 14, color: MarginColor.textTertiary) }.buttonStyle(.plain)
        }
        .marginFont(MarginTextSize.sm)
    }
}

// MARK: 1h Delete

struct DeleteNoteDialog: View {
    let note: NoteSummary
    @Environment(Workspace.self) private var workspace
    @State private var backlinks = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Icon("delete", size: 28, color: MarginColor.due)
            Text("Delete “\(note.title)”?").marginFont(MarginTextSize.lg, .semibold)
            Text(detail).marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary).lineSpacing(3)
            HStack(spacing: 10) {
                Spacer()
                MarginButton("Cancel") { workspace.dialog = nil }.keyboardShortcut(.cancelAction)
                if backlinks > 0 { MarginButton("Delete, keep links") { delete() } }
                Button { delete() } label: {
                    Text("Delete note").marginFont(MarginTextSize.base, .medium).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(MarginColor.due, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.dialog))
        .marginShadow(.modal)
        .task { backlinks = (try? await workspace.env.analysis.backlinks(id: note.id).count) ?? 0 }
    }

    private var detail: String {
        var parts: [String] = []
        if backlinks > 0 { parts.append("\(backlinks == 1 ? "1 note links" : "\(backlinks) notes link") here; the links stay as unresolved links, so you can recreate the note later.") }
        if note.openTasks > 0 { parts.append("\(note.openTasks) open tasks will be removed from Today.") }
        parts.append("The file goes to the Trash; you can restore it from there.")
        return parts.joined(separator: " ")
    }

    private func delete() { workspace.trash(note) }
}

// MARK: 2c Move note

struct MoveNoteDialog: View {
    let notes: [NoteSummary]
    private var note: NoteSummary { notes[0] }
    @Environment(Workspace.self) private var workspace
    @State private var query = ""
    @State private var selection = 0
    @State private var archived: [Course] = []

    private var targets: [Course] {
        workspace.courses.cards.map(\.course).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// 2d: archived courses are listed, read-only, so the picker shows where everything is.
    private var archivedMatches: [Course] {
        archived.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Icon("drive_file_move", size: 20, color: MarginColor.textSecondary)
                TextField(notes.count == 1 ? "Move “\(CourseDetailModel.split(note).0)” to…" : "Move \(notes.count) notes to…", text: $query)
                    .textFieldStyle(.plain).marginFont(16)
                    .onSubmit { if targets.indices.contains(selection) { move(targets[selection]) } }
            }
            .padding(.horizontal, 14).frame(height: 48)
            MarginDivider(color: Color(hex: 0xEDEEF1))
            VStack(alignment: .leading, spacing: 1) {
                PopupSection(title: workspace.courses.semester?.name ?? "Courses")
                ForEach(Array(targets.enumerated()), id: \.element.id) { i, c in
                    Button { move(c) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color(hexString: c.style.dot)).frame(width: 7, height: 7)
                            Text(c.name).frame(maxWidth: .infinity, alignment: .leading)
                            if notes.allSatisfy({ $0.courseID == c.id }) { Text("current").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary) }
                            else if i == selection { Text("↵").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary) }
                        }
                        .marginFont(14).padding(.horizontal, 8).frame(height: 32)
                        .background(i == selection ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(notes.allSatisfy { $0.courseID == c.id })
                }
                ForEach(archivedMatches) { c in
                    HStack(spacing: 10) {
                        Circle().fill(MarginColor.textDisabled).frame(width: 7, height: 7)
                        Text(c.name).frame(maxWidth: .infinity, alignment: .leading)
                        Text((workspace.courses.semesters.first { $0.id == c.semester }?.name).map { "\($0) · archived" } ?? "archived")
                            .marginFont(MarginTextSize.xs)
                    }
                    .marginFont(14).foregroundStyle(MarginColor.textDisabled)
                    .padding(.horizontal, 8).frame(height: 32)
                    .help("Archived courses are read-only")
                }
                Text("Links to this note update automatically").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                    .padding(8)
            }
            .padding(5)
        }
        .frame(width: 420)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .marginShadow(.modal)
        .task { archived = (try? await workspace.env.courses.archivedCourses()) ?? [] }
        .onKeyPress(.downArrow) { selection = min(selection + 1, targets.count - 1); return .handled }
        .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
    }

    private func move(_ course: Course) {
        workspace.perform(notes.count == 1 ? "Move note" : "Move notes") {
            for note in notes where note.courseID != course.id {
                _ = try await workspace.env.notes.move(id: note.id, toCourse: course.id, actor: .user, baseVersion: nil,
                                                       dryRun: false, idempotencyKey: nil)
            }
            workspace.dialog = nil
            workspace.noteSelection = []
            workspace.show("Moved to \(course.name)", icon: "drive_file_move")
            await workspace.refreshAfterWrite()
        }
    }
}

// MARK: 2e Enter a grade

struct GradeDialog: View {
    let courseID: CourseID
    @Environment(Workspace.self) private var workspace
    @State private var grades: [Grade] = []
    @State private var item = ""
    @State private var score = ""
    @State private var max = "20"
    @State private var weight = ""
    @State private var summary: GradeSummary?

    var body: some View {
        DialogCard(title: "Add grade", width: 420) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Graded item")
                Picker("", selection: $item) {
                    ForEach(grades.filter { $0.score == nil }) { g in Text(g.item).tag(g.item) }
                    Text("Other…").tag("")
                }
                .labelsHidden()
                if item.isEmpty || !grades.contains(where: { $0.item == item }) {
                    MarginField(placeholder: "Problem set 2", text: $item)
                }
            }
            HStack(spacing: 8) {
                MarginField(placeholder: "18", text: $score).frame(width: 90)
                    .overlay {
                        if invalid != nil {
                            RoundedRectangle(cornerRadius: MarginRadius.sm).strokeBorder(MarginColor.due)
                            RoundedRectangle(cornerRadius: MarginRadius.sm + 3).stroke(MarginColor.dueSoft, lineWidth: 3).padding(-2)
                        }
                    }
                Text("/").foregroundStyle(MarginColor.textTertiary)
                MarginField(placeholder: "20", text: $max).frame(width: 90)
                Spacer()
                if let pct = percent, invalid == nil { Text("\(Int(pct.rounded()))%\(weightText)").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary) }
            }
            if let invalid {
                // 3g validation bubble under the field.
                HStack(spacing: 8) {
                    Icon("error", size: 15, color: .white)
                    Text(invalid).font(.margin(13)).foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color(hex: 0xC4362B), in: RoundedRectangle(cornerRadius: 7))
                .shadow(color: Color(hex: 0xC4362B, opacity: 0.25), radius: 8, y: 6)
            }
            if let summary { Text("Course so far: \(summary.letter) · \(summary.percent)%").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary) }
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Save", kind: .primary) { save() }.disabled(percent == nil || item.isEmpty || invalid != nil).keyboardShortcut(.defaultAction)
        }
        .task {
            grades = (try? await workspace.env.grades.grades(course: courseID)) ?? []
            summary = try? await workspace.env.grades.average(course: courseID)
            if let first = grades.first(where: { $0.score == nil }) { item = first.item }
        }
    }

    private var percent: Double? {
        guard let s = Double(score.replacingOccurrences(of: ",", with: ".")), let m = Double(max), m > 0 else { return nil }
        return s / m * 100
    }

    /// „Score can’t be higher than 20“ and friends (3g).
    private var invalid: String? {
        guard !score.isEmpty else { return nil }
        guard let s = Double(score.replacingOccurrences(of: ",", with: ".")) else { return "Enter a number" }
        guard let m = Double(max), m > 0 else { return "The maximum must be more than 0" }
        if s < 0 { return "Score can’t be negative" }
        if s > m { return "Score can’t be higher than \(CourseDetailModel.number(m))" }
        return nil
    }

    private var weightText: String {
        (grades.first { $0.item == item }?.weightPercent).map { " · counts \($0)%" } ?? ""
    }

    private func save() {
        guard let s = Double(score.replacingOccurrences(of: ",", with: ".")), let m = Double(max) else { return }
        let existing = grades.first { $0.item == item }
        let grade = Grade(id: existing?.id ?? "grade-\(courseID)-\(item.lowercased().replacingOccurrences(of: " ", with: "-"))",
                          courseID: courseID, item: item, group: existing?.group, weightPercent: existing?.weightPercent,
                          score: s, max: m, date: existing?.date ?? workspace.env.clock.today)
        workspace.perform("Save grade") {
            _ = try await workspace.env.grades.add(grade, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            workspace.dialog = nil
            let after = try? await workspace.env.grades.average(course: courseID)
            workspace.show("Saved · course \(after.map { "\($0.percent)%" } ?? "")", icon: "bar_chart")
            await workspace.refreshAfterWrite()
        }
    }
}

// MARK: 2d Import from syllabus

struct SyllabusDialog: View {
    let courseID: CourseID
    @Environment(Workspace.self) private var workspace
    @State private var draft = SyllabusDraft()
    @State private var loaded = false

    var body: some View {
        DialogCard(title: "Import syllabus", icon: "upload_file", width: 520) {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text(summary).marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array((draft.sessions ?? []).enumerated()), id: \.offset) { i, s in
                            row("\(s.kind)", "\(CoursesFormat.weekday(s.day)) \(CoursesFormat.hour(s.start)) · \(CourseDetailModel.number(s.lengthHours)) h\(s.room.map { " · \($0)" } ?? "")") {
                                draft.sessions?.remove(at: i)
                            }
                        }
                        ForEach(Array((draft.exams ?? []).enumerated()), id: \.offset) { i, e in
                            row(e.title, "\(CourseDetailModel.day(e.date)) · \(e.weightPercent)%") { draft.exams?.remove(at: i) }
                        }
                        ForEach(Array((draft.grading ?? []).enumerated()), id: \.offset) { i, g in
                            row(g.label, "\(g.weightPercent)% of the grade") { draft.grading?.remove(at: i) }
                        }
                    }
                }
                .frame(maxHeight: 320)
                ForEach(draft.warnings, id: \.self) { w in
                    Text(w).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.warningText)
                }
                Text("Reading PDFs comes later; this is the schedule, exams and grading on file, ready to edit.")
                    .marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
            }
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Import \(count) items", kind: .primary) { apply() }.disabled(count == 0)
        }
        .task {
            draft = (try? await workspace.env.syllabus.draft(course: courseID)) ?? SyllabusDraft()
            loaded = true
        }
    }

    private var count: Int { (draft.sessions?.count ?? 0) + (draft.exams?.count ?? 0) + (draft.grading?.count ?? 0) }
    private var summary: String {
        "Found \(draft.sessions?.count ?? 0) sessions, \(draft.exams?.count ?? 0) exams and \(draft.grading?.count ?? 0) grading parts."
    }

    private func row(_ title: String, _ meta: String, remove: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).marginFont(MarginTextSize.base)
                Text(meta).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
            }
            Spacer()
            Button(action: remove) { Icon("close", size: 14, color: MarginColor.textTertiary) }.buttonStyle(.plain).help("Leave out")
        }
        .padding(10)
        .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
    }

    private func apply() {
        workspace.perform("Import syllabus") {
            _ = try await workspace.env.syllabus.apply(draft, to: courseID, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            workspace.dialog = nil
            workspace.show("Imported \(count) items", icon: "upload_file")
            await workspace.refreshAfterWrite()
        }
    }
}

// MARK: 3b Share / Export

struct ShareDialog: View {
    let note: NoteSummary
    @Environment(Workspace.self) private var workspace
    @State private var tab = 1
    @State private var frontmatter = false

    var body: some View {
        DialogCard(title: note.title, width: 460) {
            Segmented([(0, "Share"), (1, "Export")], selection: $tab).fixedSize()
            if tab == 0 {
                VStack(alignment: .leading, spacing: 10) {
                    MarginField(placeholder: "Add classmates by email", text: .constant("")).disabled(true)
                    Text("Sharing with classmates needs sync, which is not part of this version. Export a PDF or Markdown copy instead.")
                        .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    exportRow("PDF", "picture_as_pdf", .pdf)
                    exportRow("Markdown", "code", .markdown)
                    MenuRow(title: "Anki deck", icon: "style", disabled: true, help: "Flashcards come with the in-app agent") {}
                    MenuRow(title: "Word", icon: "description", disabled: true, help: "Not supported yet") {}
                    Toggle("Include properties (frontmatter) in Markdown", isOn: $frontmatter)
                        .toggleStyle(.checkbox).marginFont(MarginTextSize.sm)
                }
            }
        } footer: {
            MarginButton("Done") { workspace.dialog = nil }
        }
    }

    private func exportRow(_ title: String, _ icon: String, _ format: ExportFormat) -> some View {
        MenuRow(title: title, icon: icon, shortcut: "Export…") { export(format) }
    }

    private func export(_ format: ExportFormat) {
        workspace.perform("Export") {
            let file = try await workspace.env.export.export(note: note.id, format: format,
                                                             options: ExportOptions(includeFrontmatter: frontmatter))
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.fileName
            panel.allowedContentTypes = [format == .pdf ? .pdf : UTType(filenameExtension: "md") ?? .plainText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try file.data.write(to: url, options: .atomic)
            workspace.show("Exported \(url.lastPathComponent)", icon: "ios_share")
        }
    }
}

// MARK: 3a Archive semester

struct ArchiveSemesterDialog: View {
    let semester: Semester
    @Environment(Workspace.self) private var workspace
    @State private var openTasks = 0

    var body: some View {
        DialogCard(title: semester.isArchived ? "Restore \(semester.name)?" : "Archive \(semester.name)?", width: 460) {
            Text(semester.isArchived
                 ? "Its courses become editable again."
                 : "It ended on \(CourseDetailModel.day(semester.end)). \(workspace.courses.cards.count) courses become read-only; they stay searchable and linkable.")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
            if !semester.isArchived {
                HStack { Text("Open tasks"); Spacer(); Text("\(openTasks)").monospacedDigit() }.marginFont(MarginTextSize.base)
            }
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton(semester.isArchived ? "Restore" : "Archive semester", kind: .primary) {
                workspace.perform("Archive semester") {
                    _ = try await workspace.env.courseWriter.setArchived(semester: semester.id, !semester.isArchived, actor: .user,
                                                                        baseVersion: nil, dryRun: false, idempotencyKey: nil)
                    workspace.dialog = nil
                    workspace.show(semester.isArchived ? "Restored \(semester.name)" : "Archived \(semester.name)", icon: "inventory_2")
                    await workspace.refreshAfterWrite()
                }
            }
        }
        .task {
            let today = (try? await workspace.env.tasks.today()) ?? []
            let upcoming = (try? await workspace.env.tasks.upcoming()) ?? []
            openTasks = (today + upcoming).filter { !$0.done && $0.kind == .task }.count
        }
    }
}

// MARK: 3c Reschedule or cancel a session

struct SessionDialog: View {
    let occurrence: SessionOccurrence
    @Environment(Workspace.self) private var workspace
    @State private var date = Date()
    @State private var time = ""
    @State private var room = ""
    @State private var cancel = false

    var body: some View {
        let course = workspace.courses.course(id: occurrence.session.courseID)
        DialogCard(title: workspace.courses.title(of: occurrence), width: 440) {
            Text("\(course?.name ?? "") · usually \(CoursesFormat.weekday(occurrence.session.day)) \(CoursesFormat.hour(occurrence.session.start))\(occurrence.session.room.map { " · \($0)" } ?? "")")
                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
            FieldLabel(text: "Move only \(CourseDetailModel.day(occurrence.date))")
            HStack(spacing: 10) {
                DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                MarginField(placeholder: "14:00", text: $time).frame(width: 90)
                MarginField(placeholder: "Room", text: $room)
            }
            .disabled(cancel)
            Toggle("Cancel this session (the note is kept)", isOn: $cancel).toggleStyle(.checkbox).marginFont(MarginTextSize.base)
            if occurrence.isOverridden {
                Button("Restore the usual time") { restore() }.buttonStyle(.plain).foregroundStyle(MarginColor.accentText)
            }
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Save", kind: .primary) { save() }.keyboardShortcut(.defaultAction)
        }
        .onAppear {
            time = occurrence.session.start.string
            room = occurrence.session.room ?? ""
            cancel = occurrence.isCancelled
            if let d = workspace.env.clock.date(from: occurrence.start) { date = d }
        }
    }

    private func save() {
        let day = workspace.env.clock.localDateTime(from: date).date
        let t = LocalTime(string: time) ?? occurrence.session.start
        let override = SessionOverride(sessionID: occurrence.session.id, courseID: occurrence.session.courseID,
                                       originalDate: occurrence.originalDate, cancelled: cancel,
                                       newStart: cancel ? nil : LocalDateTime(date: day, time: t),
                                       newRoom: room.isEmpty || room == occurrence.session.room ? nil : room)
        workspace.perform("Reschedule") {
            _ = try await workspace.env.courseWriter.override(session: override, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            workspace.dialog = nil
            workspace.show(cancel ? "Session cancelled" : "Session moved", icon: "event")
            await workspace.refreshAfterWrite()
        }
    }

    private func restore() {
        workspace.perform("Restore session") {
            _ = try await workspace.env.courseWriter.clearOverride(sessionID: occurrence.session.id, course: occurrence.session.courseID,
                                                                  originalDate: occurrence.originalDate, actor: .user,
                                                                  baseVersion: nil, dryRun: false, idempotencyKey: nil)
            workspace.dialog = nil
            await workspace.refreshAfterWrite()
        }
    }
}

// MARK: 2f Course menu dialogs

struct RenameCourseDialog: View {
    let course: Course
    @Environment(Workspace.self) private var workspace
    @State private var name = ""
    @State private var folder = true

    var body: some View {
        DialogCard(title: "Rename course", width: 420) {
            MarginField(placeholder: course.name, text: $name)
            Toggle("Rename the folder too (links are updated)", isOn: $folder).toggleStyle(.checkbox).marginFont(MarginTextSize.sm)
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Rename", kind: .primary) {
                let new = name.trimmingCharacters(in: .whitespaces)
                workspace.perform("Rename course") {
                    _ = try await workspace.env.courseWriter.rename(id: course.id, to: new, renameFolder: folder, actor: .user,
                                                                   baseVersion: nil, dryRun: false, idempotencyKey: nil)
                    workspace.dialog = nil
                    await workspace.refreshAfterWrite()
                    workspace.refreshTabTitles()
                }
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction)
        }
        .onAppear { name = course.name }
    }
}

struct CourseStyleDialog: View {
    let course: Course
    @Environment(Workspace.self) private var workspace
    @State private var color = ""
    @State private var icon = ""

    var body: some View {
        DialogCard(title: "Colour and icon", width: 440) {
            HStack(spacing: 14) {
                CourseTile(style: CoursePalette.style(icon: icon, color: color), size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name).marginFont(MarginTextSize.md, .semibold).lineLimit(2)
                    if !course.code.isEmpty {
                        Text(course.code).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                    }
                }
            }
            CourseStylePicker(courseName: course.name, color: $color, icon: $icon)
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Save", kind: .primary) {
                workspace.perform("Change style") {
                    _ = try await workspace.env.courseWriter.setStyle(id: course.id, icon: icon, color: color, actor: .user,
                                                                     baseVersion: nil, dryRun: false, idempotencyKey: nil)
                    workspace.dialog = nil
                    await workspace.refreshAfterWrite()
                    workspace.refreshTabTitles()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .onAppear { color = course.style.color; icon = course.style.icon }
    }
}

/// 2f: the course menu, used on cards, rail circles and the course sidebar.
struct CourseMenuItems: View {
    let course: Course
    @Environment(Workspace.self) private var workspace

    var body: some View {
        Button("New lecture note") { workspace.newNote(in: workspace.courseModel(course.id)) }
        Button("Open") { workspace.open(course: course) }
        Button("Open in new tab") { workspace.open(.course(course.id), title: course.name, newTab: true) }
        Divider()
        Button("Course settings…") { workspace.dialog = .courseSettings(course) }
        Button("Rename…") { workspace.dialog = .renameCourse(course) }
        Button("Change colour and icon") { workspace.dialog = .courseStyle(course) }
        Button("Import syllabus…") { workspace.dialog = .syllabus(course.id) }
        Button("Enter a grade…") { workspace.dialog = .grade(course.id) }
        Divider()
        Button("Archive course") { workspace.setCourseArchived(course, true) }
        Button("Delete course…", role: .destructive) { workspace.dialog = .deleteCourse(course) }
    }
}

/// Right-click on anything that stands for a course (sidebar rows, course titles): the course
/// menu (2f). Without a course or a workspace the view is left as it is.
struct CourseContextMenu: ViewModifier {
    let courseID: String?
    @Environment(Workspace.self) private var workspace: Workspace?

    func body(content: Content) -> some View {
        if let courseID, let workspace, let course = workspace.courses.course(id: courseID) {
            content.contextMenu { CourseMenuItems(course: course).environment(workspace) }
        } else {
            content
        }
    }
}

/// The course menu as a submenu („Course ▸“) inside another context menu (timetable blocks).
struct CourseSubmenu: View {
    let courseID: String
    @Environment(Workspace.self) private var workspace: Workspace?

    var body: some View {
        if let workspace, let course = workspace.courses.course(id: courseID) {
            Menu(course.name) { CourseMenuItems(course: course).environment(workspace) }
        }
    }
}

/// Help › Keyboard shortcuts, Markdown guide, What's new.
struct HelpDialog: View {
    let topic: Workspace.HelpTopic
    @Environment(Workspace.self) private var workspace

    /// Every shortcut worth knowing (Help › Keyboard shortcuts, Settings › Keyboard shortcuts).
    static let shortcutRows: [(String, String)] =
            [("Command palette", "⌘K"), ("Quick capture from any app", "⇧⌘Space"), ("New note", "⌘N"),
             ("New lecture note", "⌃⌘N"), ("Search vault", "⇧⌘F"), ("Reading view", "⌘E"), ("Source mode", "⇧⌘E"),
             ("Sidebar", "⌘\\"), ("Right panel", "⌥⌘\\"), ("Today · Upcoming · Inbox · Schedule", "⌘1 · ⌘2 · ⌘3 · ⌘4"),
             ("Back · Forward", "⌥⌘← · ⌥⌘→"), ("Next · previous lecture", "⌃⌘→ · ⌃⌘←"), ("Task", "⌘L"),
             ("Link to note", "⇧⌘K"), ("Bold · Italic · Underline", "⌘B · ⌘I · ⌘U"), ("Checklist", "⇧⌘9"),
             ("Settings", "⌘,"), ("New tab · Close tab", "⌘T · ⌘W"), ("Next · previous tab", "⌃⇥ · ⌃⇧⇥")]

    private var rows: [(String, String)] {
        switch topic {
        case .shortcuts: Self.shortcutRows
        case .markdown:
            [("# Heading", "Heading, ## smaller"), ("**bold**  *italic*", "Emphasis"), ("- item", "Bulleted list"),
             ("- [ ] task @Fri", "Task with a due date (Today, Upcoming)"), ("[[Note]]", "Link to a note; [[Note|text]] shows text"),
             ("#tag", "Tag"), ("> [!note]", "Callout"), ("```", "Code block"), ("$$ … $$", "Formula"), ("---", "Divider")]
        case .whatsNew:
            [("Menu bar", "Every command with its shortcut, Help finds them by name"), ("Tooltips", "Shortcuts and explanations on hover"),
             ("Quick capture", "⇧⌘Space from any app, parsed course and date"), ("Your vault", "Plain Markdown files, Obsidian-compatible")]
        }
    }

    private var title: String {
        switch topic {
        case .shortcuts: "Keyboard shortcuts"
        case .markdown: "Markdown guide"
        case .whatsNew: "What’s new in Margin \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        }
    }

    var body: some View {
        DialogCard(title: title, width: 520) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.0) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.0).font(topic == .markdown ? .system(size: 13, design: .monospaced) : .margin(14))
                                .frame(width: 230, alignment: .leading)
                            Text(row.1).font(.margin(14)).foregroundStyle(MarginColor.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { MarginDivider(color: MarginColor.hover) }
                    }
                }
            }
            .frame(maxHeight: 420)
        } footer: {
            MarginButton("Done", kind: .primary) { workspace.dialog = nil }.keyboardShortcut(.defaultAction)
        }
    }
}
