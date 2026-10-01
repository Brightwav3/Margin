import MarginCore
import Observation
import SwiftUI

/// Inbox with triage (5b, M8-07/08/09): pick a course, a time and what to keep it as.
@MainActor @Observable
public final class InboxModel {
    public enum When: String, CaseIterable, Sendable { case today, tomorrow, beforeLecture, someday }
    public enum KeepAs: String, CaseIterable, Sendable { case task, note, lectureNote }

    public private(set) var items: [InboxItem] = []
    public var selected: String?
    public var course: CourseID?
    public var when: When = .today
    public var keepAs: KeepAs = .task
    public private(set) var isLoaded = false
    private let env: AppEnvironment

    public init(env: AppEnvironment) { self.env = env }

    public func load() async {
        items = (try? await env.inbox.items()) ?? []
        if selected == nil || !items.contains(where: { $0.id == selected }) { select(items.first) }
        isLoaded = true
    }

    public func select(_ item: InboxItem?) {
        selected = item?.id
        keepAs = item?.kind == .task ? .task : .note
        when = item?.kind == .task ? .today : .someday
    }

    public var current: InboxItem? { items.first { $0.id == selected } }

    /// Due date for a „When“ choice; „Before next lecture“ = the day before the course's next class.
    public func due(_ when: When, courses: [Course]) -> LocalDate? {
        let today = env.clock.today
        switch when {
        case .today: return today
        case .tomorrow: return today.adding(days: 1)
        case .someday: return nil
        case .beforeLecture:
            guard let c = courses.first(where: { $0.id == course }) else { return today.adding(days: 1) }
            let next = (1...7).map { today.adding(days: $0) }.first { d in c.sessions.contains { $0.day == d.weekday } }
            return next.map { max(today, $0.adding(days: -1)) }
        }
    }

    public func nextLectureDay(courses: [Course]) -> LocalDate? {
        guard let c = courses.first(where: { $0.id == course }) else { return nil }
        let today = env.clock.today
        return (1...7).map { today.adding(days: $0) }.first { d in c.sessions.contains { $0.day == d.weekday } }
    }

    /// The note of the nearest lecture (M8-09): cancelled classes are skipped and moved ones count on
    /// their new day (`LectureNoteResolver` over this and the neighbouring weeks' classes). A lecture
    /// without a note yet gets one, dated with the class.
    func lectureNote(of course: CourseID, courses: [Course]) async throws -> NoteID {
        guard let info = courses.first(where: { $0.id == course }) else { throw MarginError.notFound("Unknown course") }
        let notes = try await env.notes.notes(course: course)
        let semesters = (try? await env.courses.semesters()) ?? []
        let today = env.clock.today
        let semester = semesters.first { $0.start <= today && today <= $0.end }
        var occurrences: [SessionOccurrence] = []
        if let semester, let week = env.clock.weekOfSemester(semester) {
            for w in Set([week - 1, week, week + 1]) where w >= 1 {
                occurrences += ((try? await env.courses.sessions(week: w)) ?? []).filter { $0.session.courseID == course }
            }
        }
        let resolver = LectureNoteResolver(clock: env.clock)
        let target = occurrences.isEmpty ? resolver.resolve(course: info, notes: notes, semester: semester)
            : resolver.resolve(course: info, notes: notes, occurrences: occurrences)
        guard let target else { throw MarginError.notFound("No lecture in this course yet") }
        if let id = target.noteID { return id }
        let change = try await env.notes.create(course: course, title: target.suggestedTitle, kind: .lecture,
                                                text: "# \(target.suggestedTitle)\n\n", actor: .user, baseVersion: nil,
                                                dryRun: false, idempotencyKey: "lecture-\(course)-\(target.date.iso)")
        guard let id = change.entries.first?.noteID else { throw MarginError.notFound("The lecture note was not created") }
        _ = try? await env.properties.set(key: "date", value: .date(target.date), on: id, actor: .user,
                                          baseVersion: nil, dryRun: false, idempotencyKey: nil)
        return id
    }

    /// Files the item. „Add to lecture note“ appends it to the note of the nearest lecture (M8-09).
    public func move(courses: [Course]) async throws -> String {
        guard let item = current, let course else { throw MarginError.invalid("Pick a course first") }
        let due = due(when, courses: courses)
        switch keepAs {
        case .task, .note:
            _ = try await env.inbox.triage(item: item.id, course: course, when: due, kind: keepAs == .task ? .task : .note,
                                           actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        case .lectureNote:
            let lecture = try await lectureNote(of: course, courses: courses)
            let draft = CaptureDraft(text: item.text, course: course, due: item.kind == .task ? due : nil,
                                     kind: item.kind == .task ? .task : .note, attachTo: lecture)
            _ = try await env.capture.commit(draft, actor: .user, dryRun: false, idempotencyKey: "inbox-\(item.id)")
            _ = try await env.inbox.delete(item: item.id, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        }
        let name = courses.first { $0.id == course }?.name ?? course
        selected = nil
        await load()
        return name
    }

    public func delete() async throws {
        guard let item = current else { return }
        _ = try await env.inbox.delete(item: item.id, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        selected = nil
        await load()
    }

    static func icon(_ kind: InboxKind) -> String {
        switch kind {
        case .task: "check_box_outline_blank"
        case .note: "description"
        case .link: "link"
        case .image: "image"
        }
    }

    func meta(_ item: InboxItem) -> String {
        let kind = item.kind.rawValue.capitalized
        let today = env.clock.today
        let d = item.captured.date
        let when = d == today ? CoursesFormat.hour(item.captured.time)
            : d == today.adding(days: -1) ? "Yesterday" : CoursesFormat.weekday(d.weekday)
        return "\(kind) · \(when)"
    }
}

struct InboxView: View {
    @Bindable var model: InboxModel
    @Environment(Workspace.self) private var workspace

    var body: some View {
        Group {
            if model.isLoaded && model.items.isEmpty {
                EmptyState(icon: "inbox", title: "Inbox is empty",
                           text: "Everything you capture with ⌘⇧Space or from your phone lands here until you file it into a course.",
                           action: ("Capture something", { workspace.capture.open() }))
                    .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    list
                    MarginDivider(.vertical)
                    detail
                }
            }
        }
        .task { await model.load() }
        .onChange(of: workspace.inboxCount) { Task { await model.load() } }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inbox").marginFont(MarginTextSize.page, .bold).tracking(-0.6)
                Spacer()
                Text("\(model.items.count) to sort").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
            }
            .padding(.horizontal, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.items) { item in
                        let on = item.id == model.selected
                        Button { model.select(item) } label: {
                            HStack(spacing: 12) {
                                Icon(InboxModel.icon(item.kind), size: 18, color: MarginColor.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text.components(separatedBy: "\n").first ?? "").marginFont(MarginTextSize.base).lineLimit(1)
                                    Text(model.meta(item)).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(on ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                model.select(item)
                                workspace.perform("Delete") { try await model.delete(); await workspace.refreshInbox() }
                            }
                        }
                    }
                }
            }
            Button { workspace.capture.open() } label: {
                HStack(spacing: 10) {
                    Icon("add", size: 18, color: MarginColor.textTertiary)
                    Text("Capture something…")
                    Spacer()
                }
                .marginFont(MarginTextSize.base)
                .foregroundStyle(MarginColor.textTertiary)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
                .overlay { RoundedRectangle(cornerRadius: MarginRadius.sm).strokeBorder(MarginColor.border) }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 40)
        .frame(width: 400)
        .background(MarginColor.inspector)
    }

    @ViewBuilder
    private var detail: some View {
        if let item = model.current {
            let courses = workspace.courses.cards.map(\.course)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Captured \(CoursesFormat.hour(item.captured.time)) \(source(item.source))")
                            .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                        let lines = item.text.components(separatedBy: "\n")
                        Text(lines.first ?? "").marginFont(MarginTextSize.lg, .semibold)
                        if lines.count > 1 {
                            Text(lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary).lineSpacing(3)
                        }
                    }
                    section("Course") {
                        EqualColumnsLayout(minWidth: 150, maxColumns: 3, spacing: 8) {
                            ForEach(courses) { c in
                                let on = model.course == c.id
                                Button { model.course = c.id } label: {
                                    HStack(spacing: 10) {
                                        CourseTile(style: c.style, size: 32)
                                        Text(c.name).marginFont(MarginTextSize.sm).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(on ? Color(hex: 0xF7F9FE) : MarginColor.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(on ? MarginColor.accent : MarginColor.borderCard, lineWidth: on ? 1.5 : 1) }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    section("When") {
                        HStack(spacing: 8) {
                            FilterChip("Today", isOn: model.when == .today) { model.when = .today }
                            FilterChip("Tomorrow", isOn: model.when == .tomorrow) { model.when = .tomorrow }
                            FilterChip("Before next lecture\(model.nextLectureDay(courses: courses).map { " · \(CoursesFormat.weekday($0.weekday))" } ?? "")",
                                       isOn: model.when == .beforeLecture) { model.when = .beforeLecture }
                            FilterChip("Someday", isOn: model.when == .someday) { model.when = .someday }
                        }
                    }
                    section("Keep as") {
                        Segmented([(InboxModel.KeepAs.task, "Task"), (.note, "Note"), (.lectureNote, "Add to lecture note")],
                                  selection: $model.keepAs)
                            .fixedSize()
                    }
                    HStack(spacing: 10) {
                        Spacer()
                        MarginButton("Delete") {
                            workspace.perform("Delete") { try await model.delete(); await workspace.refreshInbox() }
                        }
                        MarginButton(model.course.flatMap { id in courses.first { $0.id == id } }.map { "Move to \($0.name)" } ?? "Pick a course",
                                     kind: .primary) {
                            workspace.perform("Move") {
                                let name = try await model.move(courses: courses)
                                await workspace.refreshInbox()
                                workspace.show("Moved to \(name)")
                            }
                        }
                        .disabled(model.course == nil)
                    }
                }
                .padding(40)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        } else {
            Text("Select an item to sort").marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func source(_ s: InboxSource) -> String {
        switch s {
        case .phone: "from your phone"
        case .quickCapture: "with quick entry"
        case .share: "from the share menu"
        default: ""
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textSecondary)
            content()
        }
    }
}
