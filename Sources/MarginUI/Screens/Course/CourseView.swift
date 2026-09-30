import MarginCore
import SwiftUI

/// Course detail (2c): header, then the page chosen in the sidebar (Gallery, Tasks, Exam prep, Grades).
struct CourseView: View {
    @Bindable var model: CourseDetailModel
    @Environment(Workspace.self) private var workspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                switch model.page {
                case .gallery: gallery
                case .tasks: TaskSection(title: "Assignments", rows: model.assignments, model: model)
                case .examPrep: TaskSection(title: "Exam prep", rows: model.examPrep, model: model)
                case .grades: CourseGradesView(model: model)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await model.load() }
        .task { await model.observeNotes() }
        .task { await model.observeTasks() }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.course?.name ?? "")
                    .marginFont(MarginTextSize.page, .bold)
                    .tracking(-0.6)
                Text(model.subtitle)
                    .marginFont(MarginTextSize.base)
                    .foregroundStyle(MarginColor.textSecondary)
            }
            Spacer(minLength: 16)
            if model.page == .gallery {
                Menu {
                    Picker("Order", selection: $model.newestFirst) {
                        Text("Newest").tag(true)
                        Text("Oldest").tag(false)
                    }
                    .pickerStyle(.inline)
                } label: {
                    OutlinedControl {
                        Icon("swap_vert", size: 20, color: MarginColor.textSecondary)
                        Text(model.newestFirst ? "Newest" : "Oldest")
                    }
                }
                .controlMenu()
                MarginButton("New note", icon: "add", kind: .primary) { newNote() }
            }
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                ForEach(CourseDetailModel.Filter.allCases, id: \.self) { f in
                    FilterChip(f.title, isOn: model.filter == f) { model.filter = f }
                }
            }
            if model.isLoaded && model.visibleCards.isEmpty {
                EmptyCourseView(onNewNote: newNote)
            } else {
                EqualColumnsLayout(minWidth: 260, maxColumns: 6, spacing: 16) {
                    ForEach(model.visibleCards) { card in
                        LectureCard(card: card, isSelected: card.id == model.selected) {
                            model.selected = card.id
                            open(card)
                        }
                        .contextMenu { cardMenu(card) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cardMenu(_ card: LectureCardData) -> some View {
        Button("Open") { open(card) }
        if let note = card.note {
            Button("Move to…") { workspace.dialog = .moveNote(note) }
            Button("Share / Export…") { workspace.dialog = .share(note) }
            Button("Version history") { workspace.dialog = .history(note.id) }
            Divider()
            Button("Delete…", role: .destructive) { workspace.dialog = .deleteNote(note) }
        }
    }

    private func open(_ card: LectureCardData) {
        switch card.source {
        case .note(let note): workspace.open(note: note)
        case .upcoming(let occurrence): workspace.open(session: occurrence)
        }
    }

    private func newNote() {
        workspace.perform("New note") {
            if let note = try await model.createNote() { workspace.open(note: note) }
        }
    }
}

/// Gallery card (2c): date (blue when upcoming) · kind, `…`, theme 20/600, meta and badge.
/// Borders: normal `#E4E5E9`, selected 1.5 blue, upcoming 1 px dashed `#C4C7CF`.
struct LectureCard: View {
    let card: LectureCardData
    var isSelected = false
    var onOpen: () -> Void = {}
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MarginRadius.md)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(card.date)
                    .marginFont(MarginTextSize.sm, .semibold)
                    .foregroundStyle(card.isUpcoming ? MarginColor.accent : MarginColor.ink)
                Text("· \(card.kind)").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                Spacer(minLength: 0)
                Icon("more_horiz", size: 20, color: MarginColor.textTertiary)
            }
            .lineLimit(1)
            Text(card.theme)
                .marginFont(MarginTextSize.lg, .semibold)
                .tracking(-0.3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(card.meta)
                    .marginFont(MarginTextSize.xs)
                    .foregroundStyle(MarginColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let badge = card.badge { Badge(badge.text, tone: badge.tone) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MarginColor.surface, in: shape)
        .overlay {
            if isSelected {
                shape.strokeBorder(MarginColor.accent, lineWidth: 1.5)
            } else if card.isUpcoming {
                shape.strokeBorder(MarginColor.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                shape.strokeBorder(hovered ? MarginColor.border : MarginColor.borderCard)
            }
        }
        .contentShape(shape)
        .onHover { hovered = $0 }
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("lecture-card-\(card.theme)")
    }
}

private struct TaskSection: View {
    let title: String
    let rows: [CourseTaskRow]
    let model: CourseDetailModel
    @Environment(Workspace.self) private var workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).marginFont(MarginTextSize.md, .semibold).padding(.leading, 12)
            if rows.isEmpty {
                Text("Nothing here yet. Write `- [ ] task` in a note of this course.")
                    .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textTertiary).padding(12)
            }
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    TaskRow(task: row.task, weight: row.weight, status: row.graded, from: row.from,
                            onToggle: { workspace.perform("Update task") { try await model.toggle(row.task) } },
                            onOpenSource: { workspace.open(task: row.task) })
                    if row.id != rows.last?.id { MarginDivider().padding(.leading, 40) }
                }
            }
        }
    }
}

/// Grade parts of a course with weight and progress (like `gradeParts`).
struct CourseGradesView: View {
    let model: CourseDetailModel
    @Environment(Workspace.self) private var workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Grades").marginFont(MarginTextSize.md, .semibold)
                Spacer()
                MarginButton("Enter a grade", icon: "add") { workspace.dialog = .grade(model.courseID) }
            }
            ForEach(GradeGroups.make(course: model.course, grades: model.grades), id: \.label) { part in
                GradePartRow(part: part)
            }
            if let g = model.grade {
                Text("Grade so far: \(g.letter) · \(g.percent)%")
                    .marginFont(MarginTextSize.base, .semibold)
                    .padding(.top, 6)
            }
        }
    }
}

/// A grading part with its weight and the graded share (M11-01 uses the same row).
struct GradePart: Sendable {
    var label: String
    var weight: Int
    /// „18/20“ or the date of the next graded item.
    var score: String
    /// 0…1 achieved so far.
    var fraction: Double
}

enum GradeGroups {
    static func make(course: Course?, grades: [Grade]) -> [GradePart] {
        let parts = course?.grading ?? []
        if parts.isEmpty {
            return grades.map { g in
                GradePart(label: g.item, weight: g.weightPercent ?? 0,
                          score: g.score.map { "\(CourseDetailModel.number($0))/\(CourseDetailModel.number(g.max ?? 0))" }
                              ?? g.date.map { CourseDetailModel.day($0) } ?? "—",
                          fraction: (g.percent ?? 0) / 100)
            }
        }
        return parts.map { part in
            let items = grades.filter { ($0.group ?? $0.item) == part.label }
            let scored = items.filter { $0.score != nil }
            let score = scored.reduce(0) { $0 + ($1.score ?? 0) }, max = scored.reduce(0) { $0 + ($1.max ?? 0) }
            let next = items.filter { $0.score == nil }.compactMap(\.date).min()
            let text = max > 0 ? "\(CourseDetailModel.number(score))/\(CourseDetailModel.number(max))"
                : next.map { CourseDetailModel.day($0) } ?? "—"
            return GradePart(label: part.label, weight: part.weightPercent, score: text,
                             fraction: max > 0 ? score / max : 0)
        }
    }
}

struct GradePartRow: View {
    let part: GradePart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(part.label).marginFont(MarginTextSize.base)
                Text("\(part.weight)%").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                Spacer()
                Text(part.score).marginFont(MarginTextSize.base).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MarginColor.borderSubtle)
                    Capsule().fill(MarginColor.accent).frame(width: geo.size.width * min(1, max(0, part.fraction)))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.borderCard) }
    }
}

/// Empty course (Screens 2a): import the syllabus or write the first note.
struct EmptyCourseView: View {
    var onNewNote: () -> Void
    var onSyllabus: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Icon("description", size: 36, color: MarginColor.textTertiary)
            Text("No notes yet").marginFont(MarginTextSize.lg, .semibold)
            Text("Notes for each class appear here. Start with the syllabus or write the first note.")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                if let onSyllabus { MarginButton("Import syllabus", icon: "upload_file", action: onSyllabus) }
                MarginButton("Create first note", icon: "edit_square", kind: .primary, action: onNewNote)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
