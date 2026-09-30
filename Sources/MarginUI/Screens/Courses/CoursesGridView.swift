import MarginCore
import SwiftUI

/// 1a „Card grid“: header with Group by / Sort / New course, faculty chips and the card grid
/// (3 columns, gap 16; 2 or 1 when the window is narrower, see `columns(for:)`).
struct CoursesGridView: View {
    @Bindable var model: CoursesOverviewModel
    var onOpen: (Course) -> Void = { _ in }
    var onNewCourse: () -> Void = {}
    @State private var selected: CourseID?

    /// Narrowest card before the grid drops a column (2 columns at a 900 px window).
    static let minCardWidth: CGFloat = 260
    static let gap: CGFloat = 16

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                chips
                ForEach(Array(model.groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 12) {
                        if let title = group.title {
                            GroupHeader(title: title, count: group.cards.count)
                        }
                        grid(group.cards)
                    }
                }
                if model.isLoaded && model.visibleCards.isEmpty {
                    Text("No courses in this group.")
                        .marginFont(MarginTextSize.base)
                        .foregroundStyle(MarginColor.textTertiary)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .onChange(of: model.visibleCards.map(\.id), initial: true) { _, ids in
            if selected == nil || !ids.contains(selected ?? "") { selected = ids.first }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your courses")
                    .marginFont(MarginTextSize.page, .bold)
                    .tracking(-0.6)
                Text(model.semesterLine)
                    .marginFont(MarginTextSize.base)
                    .foregroundStyle(MarginColor.textSecondary)
            }
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                Menu {
                    Picker("Group by", selection: $model.grouping) {
                        Text("Faculty").tag(CoursesOverviewModel.Grouping.faculty)
                        Text("None").tag(CoursesOverviewModel.Grouping.none)
                    }
                    .pickerStyle(.inline)
                } label: {
                    OutlinedControl {
                        Text("Group by:").foregroundStyle(MarginColor.textSecondary)
                        Text(model.grouping == .faculty ? "Faculty" : "None")
                        Icon("expand_more", size: 20, color: MarginColor.textSecondary)
                    }
                    .padding(.trailing, -2)
                }
                .controlMenu()

                Menu {
                    Picker("Sort", selection: $model.sort) {
                        Text("Name").tag(CourseListQuery.SortKey.name)
                        Text("Code").tag(CourseListQuery.SortKey.code)
                        Text("Next class").tag(CourseListQuery.SortKey.nextSession)
                        Text("Open tasks").tag(CourseListQuery.SortKey.dueCount)
                    }
                    .pickerStyle(.inline)
                } label: {
                    OutlinedControl {
                        Icon("swap_vert", size: 20, color: MarginColor.textSecondary)
                        Text("Sort")
                    }
                }
                .controlMenu()

                MarginButton("New course", icon: "add", kind: .primary, action: onNewCourse)
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            FilterChip("All courses", isOn: model.faculty == nil) { model.faculty = nil }
            ForEach(model.faculties, id: \.self) { name in
                FilterChip(name, isOn: model.faculty == name) { model.faculty = name }
            }
        }
    }

    private func grid(_ cards: [CourseCardData]) -> some View {
        EqualColumnsLayout(minWidth: Self.minCardWidth, maxColumns: 3, spacing: Self.gap) {
            ForEach(cards) { card in
                CourseCard(data: card, isSelected: card.id == selected) {
                    selected = card.id
                    onOpen(card.course)
                }
            }
        }
    }
}

/// Faculty heading when grouping. Not in the mockup (Group by is only a control there):
/// **proposal** — name 15/600, count 13 tertiary, awaiting approval in `docs/checks/M3.md`.
private struct GroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).marginFont(MarginTextSize.base, .semibold)
            Text("\(count)").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
        }
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 40 px outlined control label (Group by, Sort) matching the secondary button.
struct OutlinedControl<Label: View>: View {
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MarginRadius.sm)
        HStack(spacing: 6) { label }
            .marginFont(MarginTextSize.base)
            .foregroundStyle(MarginColor.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(hovered ? MarginColor.sunken : MarginColor.surface, in: shape)
            .overlay { shape.strokeBorder(MarginColor.border) }
            .contentShape(shape)
            .onHover { hovered = $0 }
    }
}

extension View {
    /// A `Menu` that shows its custom label as is.
    func controlMenu() -> some View {
        menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

/// CSS `grid-template-columns: repeat(n, minmax(0, 1fr))` with `n` chosen from the width:
/// as many columns as fit `minWidth` (at most `maxColumns`); rows as tall as their tallest card.
struct EqualColumnsLayout: Layout {
    var minWidth: CGFloat
    var maxColumns: Int
    var spacing: CGFloat

    func columns(for width: CGFloat) -> Int {
        max(1, min(maxColumns, Int((width + spacing) / (minWidth + spacing))))
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> (columnWidth: CGFloat, heights: [CGFloat], columns: Int) {
        let n = columns(for: width)
        let columnWidth = max(0, (width - spacing * CGFloat(n - 1)) / CGFloat(n))
        var heights: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: n) {
            let row = subviews[start..<min(start + n, subviews.count)]
            heights.append(row.map { $0.sizeThatFits(.init(width: columnWidth, height: nil)).height }.max() ?? 0)
        }
        return (columnWidth, heights, n)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? (minWidth * CGFloat(maxColumns) + spacing * CGFloat(maxColumns - 1))
        let r = rows(subviews, width: width)
        let height = r.heights.reduce(0, +) + spacing * CGFloat(max(0, r.heights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rows(subviews, width: bounds.width)
        var y = bounds.minY
        for (rowIndex, height) in r.heights.enumerated() {
            for column in 0..<r.columns {
                let index = rowIndex * r.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (r.columnWidth + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: .init(width: r.columnWidth, height: height))
            }
            y += height + spacing
        }
    }
}
