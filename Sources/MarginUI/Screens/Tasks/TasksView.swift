import MarginCore
import SwiftUI

/// Today and Upcoming pages (M7-05, M7-06).
struct TasksView: View {
    @Bindable var model: TasksModel
    @Environment(Workspace.self) private var workspace
    @State private var picking: TaskItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.scope == .today && !model.sessions.isEmpty { classes }
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.title).marginFont(MarginTextSize.md, .semibold)
                                .foregroundStyle(group.id == "overdue" ? MarginColor.due : MarginColor.ink)
                            if let detail = group.detail {
                                Text(detail).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                            }
                            Spacer()
                            Text("\(group.tasks.count)").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        MarginDivider()
                        if group.tasks.isEmpty {
                            Text(model.scope == .today ? "Nothing due today." : "Nothing here.")
                                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textTertiary).padding(12)
                        }
                        ForEach(group.tasks) { task in row(task) }
                    }
                }
                if model.isLoaded && model.groups.allSatisfy({ $0.tasks.isEmpty }) && model.scope == .upcoming {
                    EmptyState(icon: "calendar_today", title: "Nothing coming up",
                               text: "Tasks with a date (`- [ ] … @Fri`) in any note appear here.")
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await model.load() }
        .task { await model.observe() }
        .popover(item: $picking) { task in
            DuePicker(task: task, course: task.source.courseID.flatMap { workspace.courses.course(id: $0) }) { due in
                picking = nil
                workspace.perform("Set due date") { try await model.setDue(task, due) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Icon(model.scope == .today ? "light_mode" : "calendar_today", size: 28,
                     color: model.scope == .today ? MarginColor.warningText : MarginColor.due)
                Text(model.scope == .today ? "Today" : "Upcoming").marginFont(MarginTextSize.page, .bold).tracking(-0.6)
            }
            Text(subtitle).marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
        }
    }

    private var subtitle: String {
        let d = model.today
        let date = "\(CoursesFormat.weekdayName(d.weekday)) \(d.day) \(CoursesFormat.month(d.month))"
        let n = model.count
        return "\(date) · \(n == 1 ? "1 open task" : "\(n) open tasks")"
    }

    private var classes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Classes today").marginFont(MarginTextSize.md, .semibold).padding(.horizontal, 12)
            HStack(spacing: 12) {
                ForEach(model.sessions) { s in
                    let course = workspace.courses.course(id: s.session.courseID)
                    let past = s.start < workspace.env.clock.localNow
                    Button { workspace.open(session: s) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(CoursesFormat.hour(s.session.start))–\(CoursesFormat.hour(s.session.end))")
                                .marginFont(MarginTextSize.sm, .semibold)
                            Text(course?.name ?? s.session.courseID).marginFont(MarginTextSize.base, .semibold).lineLimit(1)
                            Text([s.session.kind, s.session.room ?? course?.room].compactMap { $0 }.joined(separator: " · "))
                                .marginFont(MarginTextSize.xs).opacity(0.85)
                        }
                        .foregroundStyle(Color(hexString: course?.style.foreground ?? "#1C1E26"))
                        .padding(12)
                        .frame(width: 200, alignment: .leading)
                        .background(Color(hexString: course?.style.background ?? "#F3F4F6"), in: RoundedRectangle(cornerRadius: MarginRadius.md))
                        .opacity(past ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskRow(task: task, course: task.source.courseID.flatMap { workspace.courses.course(id: $0) },
                from: task.source.noteID.isEmpty ? nil : noteTitle(task),
                onToggle: { workspace.perform("Update task") { try await model.toggle(task) } },
                onOpenSource: { workspace.open(task: task) })
            .contextMenu {
                Button("Open note") { workspace.open(task: task) }
                Button("Due today") { workspace.perform("Set due date") { try await model.setDue(task, model.today) } }
                Button("Due tomorrow") { workspace.perform("Set due date") { try await model.setDue(task, model.today.adding(days: 1)) } }
                Button("Due…") { picking = task }
                Button("Remove due date") { workspace.perform("Set due date") { try await model.setDue(task, nil) } }
            }
            .onTapGesture(count: 2) { workspace.open(task: task) }
            .accessibilityAction(named: "Open in note") { workspace.open(task: task) }
    }

    private func noteTitle(_ task: TaskItem) -> String {
        workspace.courses.notes(of: task.source.courseID ?? "").first { $0.id == task.source.noteID }
            .map { CourseDetailModel.split($0).0 == "Note" || CourseDetailModel.split($0).0 == "Study note" ? $0.title : CourseDetailModel.split($0).0 }
            ?? "Note"
    }
}

/// 1f Due date picker: quick choices (Today, Tomorrow, before the next class, before the next exam)
/// and a month calendar.
struct DuePicker: View {
    let task: TaskItem
    let course: Course?
    let choose: (LocalDate?) -> Void
    @Environment(Workspace.self) private var workspace
    @State private var date = Date()

    var body: some View {
        let today = workspace.env.clock.today
        VStack(alignment: .leading, spacing: 2) {
            Text(task.text).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary).lineLimit(1)
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            MenuRow(title: "Today", icon: "light_mode", shortcut: CourseDetailModel.day(today)) { choose(today) }
            MenuRow(title: "Tomorrow", icon: "wb_twilight", shortcut: CourseDetailModel.day(today.adding(days: 1))) {
                choose(today.adding(days: 1))
            }
            if let next = nextClass(after: today) {
                MenuRow(title: "Before next lecture", icon: "event_upcoming", shortcut: CourseDetailModel.day(next)) {
                    choose(next.adding(days: -1) < today ? today : next.adding(days: -1))
                }
            }
            if let exam = course?.exams.filter({ $0.date > today }).min(by: { $0.date < $1.date }) {
                MenuRow(title: "Before \(exam.title.lowercased())", icon: "quiz", shortcut: CourseDetailModel.day(exam.date)) {
                    choose(exam.date.adding(days: -1))
                }
            }
            MarginDivider(color: Color(hex: 0xEDEEF1)).padding(.vertical, 4)
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .onChange(of: date) { _, new in
                    choose(workspace.env.clock.localDateTime(from: new).date)
                }
            if task.due != nil {
                MenuRow(title: "Remove due date", icon: "event_busy", destructive: true) { choose(nil) }
            }
        }
        .padding(6)
        .frame(width: 260)
        .onAppear {
            if let due = task.due, let d = workspace.env.clock.date(from: LocalDateTime(date: due, time: LocalTime(hour: 12, minute: 0)!)) {
                date = d
            }
        }
    }

    private func nextClass(after day: LocalDate) -> LocalDate? {
        guard let course else { return nil }
        return (1...7).map { day.adding(days: $0) }.first { d in course.sessions.contains { $0.day == d.weekday } }
    }
}

/// Generic empty state (Screens 2a/2b).
struct EmptyState: View {
    let icon: String
    let title: String
    let text: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Icon(icon, size: 36, color: MarginColor.textTertiary)
            Text(title).marginFont(MarginTextSize.lg, .semibold)
            Text(text).marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary).multilineTextAlignment(.center)
            if let action { MarginButton(action.title, kind: .primary, action: action.run) }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
