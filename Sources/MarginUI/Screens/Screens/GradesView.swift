import MarginCore
import Observation
import SwiftUI

/// Screens 1e Grades across the semester (M11-01.U): a row per course (grade, so far, next graded
/// item), the selected course's parts, and what is needed on the rest for a target grade.
@MainActor @Observable
public final class GradesModel {
    public struct Row: Identifiable, Sendable {
        public var id: CourseID { course.id }
        public var course: Course
        public var summary: GradeSummary?
        public var grades: [Grade]
        /// „Midterm · Thu“.
        public var next: String?
    }

    public private(set) var rows: [Row] = []
    public var selected: CourseID?
    /// Target percentage for the „to finish with“ line (A = 93).
    public var target = 93
    private let env: AppEnvironment

    public init(env: AppEnvironment) { self.env = env }

    public func load() async {
        let courses = (try? await env.courses.courses(query: nil)) ?? []
        let today = env.clock.today
        var rows: [Row] = []
        for c in courses {
            let grades = (try? await env.grades.grades(course: c.id)) ?? []
            let summary = try? await env.grades.average(course: c.id)
            let next = grades.filter { $0.score == nil }.compactMap { g in g.date.map { (g, $0) } }
                .filter { $0.1 >= today }.min { $0.1 < $1.1 }
                .map { "\($0.0.item) · \(today.days(to: $0.1) < 7 ? CoursesFormat.weekday($0.1.weekday) : CourseDetailModel.day($0.1))" }
            rows.append(Row(course: c, summary: summary, grades: grades, next: next))
        }
        self.rows = rows
        if selected == nil { selected = rows.first { !$0.grades.isEmpty }?.id ?? rows.first?.id }
    }

    /// Semester average of the graded courses, weighted by credits (equal weights without credits).
    public var average: (percent: Double, letter: String)? {
        let graded = rows.compactMap { r in r.summary.map { (Double($0.percent), Double(r.course.credits ?? 1)) } }
        guard !graded.isEmpty else { return nil }
        let total = graded.reduce(0) { $0 + $1.1 }
        let pct = graded.reduce(0) { $0 + $1.0 * $1.1 } / total
        return (pct, Self.letter(pct))
    }

    /// Default scale of Settings › Semesters (A 93, A− 90, B+ 87, B 83, B− 80, C+ 77, C 73, C− 70, D 60).
    nonisolated static func letter(_ pct: Double) -> String {
        let scale: [(Double, String)] = [(93, "A"), (90, "A−"), (87, "B+"), (83, "B"), (80, "B−"), (77, "C+"),
                                         (73, "C"), (70, "C−"), (60, "D")]
        return scale.first { pct >= $0.0 }?.1 ?? "F"
    }

    /// Share of the course already graded, 0…100.
    public func gradedWeight(_ row: Row) -> Int {
        row.grades.filter { $0.score != nil }.reduce(0) { $0 + ($1.weightPercent ?? 0) }
    }

    /// Average needed on the remaining weight to reach `target`; nil when nothing remains.
    public func needed(_ row: Row) -> Double? {
        let graded = row.grades.filter { $0.score != nil && $0.percent != nil }
        let done = graded.reduce(0.0) { $0 + Double($1.weightPercent ?? 0) * ($1.percent ?? 0) }
        let remaining = 100 - Double(gradedWeight(row))
        guard remaining > 0 else { return nil }
        return (Double(target) * 100 - done) / remaining
    }
}

struct GradesView: View {
    @Bindable var model: GradesModel
    @Environment(Workspace.self) private var workspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Grades").marginFont(MarginTextSize.page, .bold).tracking(-0.6)
                    Text(subtitle).marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
                }
                table
                if let id = model.selected, let row = model.rows.first(where: { $0.id == id }) { detail(row) }
            }
            .padding(.horizontal, 36).padding(.vertical, 28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await model.load() }
    }

    private var subtitle: String {
        let sem = workspace.courses.semester?.name ?? ""
        guard let avg = model.average else { return "\(sem) · no grades yet" }
        return "\(sem) · weighted average \(avg.letter) · \(String(format: "%.1f", avg.percent))%"
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Course").frame(maxWidth: .infinity, alignment: .leading)
                Text("Grade").frame(width: 70, alignment: .leading)
                Text("So far").frame(width: 70, alignment: .leading)
                Text("Next graded").frame(width: 200, alignment: .leading)
            }
            .marginFont(MarginTextSize.sm, .semibold).foregroundStyle(MarginColor.textSecondary)
            .padding(.horizontal, 14).padding(.bottom, 8)
            MarginDivider()
            ForEach(model.rows) { row in
                let on = row.id == model.selected
                Button { model.selected = row.id } label: {
                    HStack {
                        HStack(spacing: 12) {
                            CourseTile(style: row.course.style, size: 32)
                            Text(row.course.name).marginFont(MarginTextSize.base)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.summary?.letter ?? "—").marginFont(MarginTextSize.base, .semibold).frame(width: 70, alignment: .leading)
                        Text(row.summary.map { "\($0.percent)%" } ?? "—").monospacedDigit().frame(width: 70, alignment: .leading)
                        Text(row.next ?? "—").foregroundStyle(MarginColor.textSecondary).frame(width: 200, alignment: .leading)
                    }
                    .marginFont(MarginTextSize.base)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(on ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detail(_ row: GradesModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(row.course.name).marginFont(MarginTextSize.md, .semibold)
                Text("\(model.gradedWeight(row))% graded").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                Spacer()
                MarginButton("Enter a grade", icon: "add", size: .small) { workspace.dialog = .grade(row.id) }
            }
            GradeChart(grades: row.grades)
            ForEach(GradeGroups.make(course: row.course, grades: row.grades), id: \.label) { GradePartRow(part: $0) }
            if let need = model.needed(row) {
                HStack(spacing: 8) {
                    Text("To finish with")
                    Picker("", selection: $model.target) {
                        ForEach([(93, "an A (93%)"), (90, "an A− (90%)"), (87, "a B+ (87%)"), (83, "a B (83%)")], id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden().fixedSize()
                    Text(need > 100 ? "you would need more than 100% on the rest." : need <= 0 ? "you are already there."
                         : "you need an average of \(Int(need.rounded()))% on the remaining \(100 - model.gradedWeight(row))%.")
                }
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
            }
        }
    }
}

/// Screens 1f Past semesters: archived semesters, read-only, with restore (M11-04.U).
struct ArchiveView: View {
    @Environment(Workspace.self) private var workspace
    @State private var archivedCourses: [Course] = []

    var body: some View {
        let archived = workspace.courses.semesters.filter(\.isArchived)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Archive").marginFont(MarginTextSize.page, .bold).tracking(-0.6)
                    Text("Read-only. Notes stay searchable and linkable.").marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
                }
                if !archivedCourses.isEmpty {
                    Text("Archived courses").marginFont(MarginTextSize.md, .semibold)
                    ForEach(archivedCourses) { c in
                        HStack(spacing: 14) {
                            CourseTile(style: c.style, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.name).marginFont(MarginTextSize.md, .semibold)
                                Text([c.code, c.professor].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                                    .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                            }
                            Spacer()
                            MarginButton("Restore", icon: "unarchive", size: .small) {
                                workspace.setCourseArchived(c, false)
                                archivedCourses.removeAll { $0.id == c.id }
                            }
                            MarginButton("Delete…", size: .small) { workspace.dialog = .deleteCourse(c) }
                        }
                        .padding(16)
                        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
                        .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.borderCard) }
                    }
                    Text("Past semesters").marginFont(MarginTextSize.md, .semibold).padding(.top, 8)
                }
                if archived.isEmpty {
                    EmptyState(icon: "inventory_2", title: "No past semesters",
                               text: "When a semester ends, archive it from Settings › Semesters or the course list; it moves here.")
                }
                ForEach(archived) { s in
                    HStack(spacing: 14) {
                        Icon("inventory_2", size: 22, color: MarginColor.textSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.name).marginFont(MarginTextSize.md, .semibold)
                            Text("\(CourseDetailModel.day(s.start)) \(s.start.year) – \(CourseDetailModel.day(s.end)) \(s.end.year)")
                                .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                        }
                        Spacer()
                        MarginButton("Search in it", icon: "search", size: .small) { workspace.open(.search("")) }
                        MarginButton("Restore…", size: .small) { workspace.dialog = .archiveSemester(s) }
                    }
                    .padding(16)
                    .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
                    .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.borderCard) }
                }
            }
            .padding(.horizontal, 36).padding(.vertical, 28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: workspace.dialog == nil) {
            archivedCourses = (try? await workspace.env.courses.archivedCourses()) ?? []
        }
    }
}

/// 3h: one bar per graded item; hover shows „Midterm · 41/50“ and „82% · counts 30%“.
struct GradeChart: View {
    let grades: [Grade]

    var body: some View {
        let items = grades.sorted { ($0.date ?? .init(daysSinceEpoch: 0)) < ($1.date ?? .init(daysSinceEpoch: 0)) }
        if !items.isEmpty {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(items) { g in
                        let pct = g.percent ?? 0
                        VStack {
                            Spacer(minLength: 0)
                            UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5)
                                .fill(g.score == nil ? MarginColor.borderSubtle : MarginColor.accentRing)
                                .frame(height: max(4, 150 * pct / 100))
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .marginTooltip(g.score == nil ? g.item : "\(g.item) · \(CourseDetailModel.number(g.score ?? 0))/\(CourseDetailModel.number(g.max ?? 0))",
                                       detail: g.score == nil ? (g.date.map { "Not graded yet · \(CourseDetailModel.day($0))" } ?? "Not graded yet")
                                           : "\(Int(pct.rounded()))%\(g.weightPercent.map { " · counts \($0)%" } ?? "")",
                                       placement: .top)
                    }
                }
                .frame(height: 150)
                .overlay(alignment: .bottom) { MarginDivider(color: MarginColor.borderCard) }
                HStack(spacing: 14) {
                    ForEach(items) { g in
                        Text(g.item).font(.margin(11)).foregroundStyle(MarginColor.textTertiary).lineLimit(1).frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}
