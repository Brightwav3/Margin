import MarginCore
import SwiftUI

/// Course settings (2f „Course settings…“): name, code, lecturer, room, faculty, credits, weekly
/// timetable and exams, written through `CourseCatalogWriter.rename` and `update`.
struct CourseSettingsDialog: View {
    let course: Course
    @Environment(Workspace.self) private var workspace
    @State private var name = ""
    @State private var code = ""
    @State private var professor = ""
    @State private var room = ""
    @State private var faculty = ""
    @State private var credits = ""
    @State private var sessions: [NewSession] = []
    @State private var exams: [NewExam] = []
    @State private var saving = false

    var body: some View {
        DialogCard(title: "Course settings", icon: "tune", width: 620) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Button { workspace.dialog = .courseStyle(course) } label: {
                            CourseTile(style: course.style, size: 52)
                        }
                        .buttonStyle(.plain).marginTooltip("Change colour and icon")
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel(text: "Name")
                            MarginField(placeholder: "Course name", text: $name)
                        }
                    }
                    HStack(spacing: 12) {
                        field("Code", "MVZb1010", $code)
                        field("Lecturer", "Optional", $professor)
                    }
                    HStack(spacing: 12) {
                        field("Room", "Optional", $room)
                        field("Faculty", "FSS MU", $faculty)
                        field("Credits", "0", $credits).frame(width: 90)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Weekly timetable")
                        if sessions.isEmpty {
                            Text("No weekly classes (block or irregular course).")
                                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                        }
                        ForEach(sessions.indices, id: \.self) { i in
                            SessionEditorRow(session: $sessions[i]) { sessions.remove(at: i) }
                        }
                        addButton("Add class") {
                            sessions.append(NewSession(day: .monday, start: LocalTime(hour: 10, minute: 0)!,
                                                       kind: sessions.last?.kind ?? "Lecture", room: room.isEmpty ? nil : room))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Exams and deadlines")
                        ForEach(exams.indices, id: \.self) { i in ExamEditorRow(exam: $exams[i], clock: workspace.env.clock) { exams.remove(at: i) } }
                        addButton("Add exam") {
                            exams.append(NewExam(title: "", date: workspace.env.clock.today.adding(days: 30), weightPercent: 0))
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 520)
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Save", kind: .primary) { save() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear(perform: fill)
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) { FieldLabel(text: label); MarginField(placeholder: placeholder, text: text) }
    }

    private func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { Icon("add", size: 16); Text(title) }
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.accentText)
        }
        .buttonStyle(.plain)
    }

    private func fill() {
        name = course.name; code = course.code; professor = course.professor ?? ""; room = course.room ?? ""
        faculty = course.faculty ?? ""; credits = course.credits.map(String.init) ?? ""
        sessions = course.sessions.map { NewSession(day: $0.day, start: $0.start, lengthHours: $0.lengthHours, kind: $0.kind, room: $0.room) }
        exams = course.exams.map { NewExam(title: $0.title, date: $0.date, time: $0.time, weightPercent: $0.weightPercent) }
    }

    private func save() {
        saving = true
        let newName = name.trimmingCharacters(in: .whitespaces)
        let update = CourseUpdate(code: code, professor: professor, room: room, faculty: faculty,
                                  credits: Int(credits.trimmingCharacters(in: .whitespaces)) ?? 0,
                                  sessions: sessions, exams: exams)
        workspace.perform("Save course settings") {
            defer { saving = false }
            let writer = workspace.env.courseWriter
            _ = try await writer.update(id: course.id, update, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            if newName != course.name {
                _ = try await writer.rename(id: course.id, to: newName, renameFolder: true, actor: .user,
                                            baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
            workspace.dialog = nil
            await workspace.refreshAfterWrite()
            workspace.refreshTabTitles()
            workspace.show("Saved \(newName)", icon: "check")
        }
    }
}

/// One exam row: title, date, optional time and weight.
struct ExamEditorRow: View {
    @Binding var exam: NewExam
    let clock: any Clock
    let remove: () -> Void

    private var date: Binding<Date> {
        Binding(get: { clock.date(from: LocalDateTime(date: exam.date, time: LocalTime(hour: 12, minute: 0)!)) ?? Date() },
                set: { exam.date = clock.localDateTime(from: $0).date })
    }

    var body: some View {
        HStack(spacing: 8) {
            Icon("quiz", size: 16, color: MarginColor.textSecondary)
            TextField("Midterm", text: $exam.title).textFieldStyle(.roundedBorder)
            DatePicker("", selection: date, displayedComponents: .date)
                .labelsHidden().datePickerStyle(.field).frame(width: 110)
            TextField("Time", text: Binding(get: { exam.time?.string ?? "" },
                                            set: { exam.time = $0.isEmpty ? nil : LocalTime(string: $0) ?? exam.time }))
                .textFieldStyle(.roundedBorder).frame(width: 56)
            HStack(spacing: 2) {
                TextField("0", value: $exam.weightPercent, format: .number).textFieldStyle(.roundedBorder).frame(width: 46)
                Text("%").foregroundStyle(MarginColor.textSecondary)
            }
            Button(action: remove) { Icon("close", size: 14, color: MarginColor.textTertiary) }.buttonStyle(.plain)
        }
        .marginFont(MarginTextSize.sm)
    }
}

/// Delete a course: the folder with all its notes and files goes to the Trash.
struct DeleteCourseDialog: View {
    let course: Course
    @Environment(Workspace.self) private var workspace
    @State private var noteCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Icon("delete", size: 28, color: MarginColor.due)
            Text("Delete “\(course.name)”?").marginFont(MarginTextSize.lg, .semibold)
            Text("The course folder with \(noteCount) \(noteCount == 1 ? "note" : "notes") and its files moves to the Trash. "
                 + "You can get it back from the Trash in Finder. To keep it out of the way instead, archive it.")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary).lineSpacing(3)
            HStack(spacing: 10) {
                Spacer()
                MarginButton("Cancel") { workspace.dialog = nil }.keyboardShortcut(.cancelAction)
                MarginButton("Archive instead") {
                    workspace.dialog = nil
                    workspace.setCourseArchived(course, true)
                }
                Button { delete() } label: {
                    Text("Delete course").marginFont(MarginTextSize.base, .medium).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(MarginColor.due, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, alignment: .leading)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.dialog))
        .marginShadow(.modal)
        .task { noteCount = (try? await workspace.env.notes.notes(course: course.id).count) ?? 0 }
    }

    private func delete() {
        workspace.perform("Delete course") {
            _ = try await workspace.env.courseWriter.delete(id: course.id, actor: .user, baseVersion: nil, dryRun: false,
                                                            idempotencyKey: nil)
            workspace.dialog = nil
            workspace.leave(course: course.id)
            await workspace.refreshAfterWrite()
            workspace.show("Moved \(course.name) to the Trash", icon: "delete")
        }
    }
}

/// A new semester: name and dates (the start snaps to its Monday, as week 1 starts on Monday).
struct NewSemesterDialog: View {
    @Environment(Workspace.self) private var workspace
    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(14 * 7 * 86_400)
    @State private var saving = false

    var body: some View {
        DialogCard(title: "New semester", icon: "school", width: 460) {
            VStack(alignment: .leading, spacing: 6) { FieldLabel(text: "Name"); MarginField(placeholder: "Jaro 2027", text: $name) }
            HStack(spacing: 16) {
                DatePicker("Starts", selection: $start, displayedComponents: .date)
                DatePicker("Ends", selection: $end, displayedComponents: .date)
            }
            .marginFont(MarginTextSize.base)
            Text("Week 1 starts on the Monday of the start date. The current semester is the one that contains today.")
                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
        } footer: {
            MarginButton("Cancel") { workspace.dialog = nil }
            MarginButton("Create semester", kind: .primary) { create() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving || end <= start)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func create() {
        saving = true
        let clock = workspace.env.clock
        let semester = NewSemester(name: name.trimmingCharacters(in: .whitespaces),
                                   start: clock.localDateTime(from: start).date.startOfWeek,
                                   end: clock.localDateTime(from: end).date)
        workspace.perform("Create semester") {
            defer { saving = false }
            _ = try await workspace.env.semesters.create(semester, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            workspace.dialog = nil
            await workspace.refreshAfterWrite()
            workspace.show("Created \(semester.name)", icon: "school")
        }
    }
}
