import MarginCore
import SwiftUI

/// 56 px rail (`Sidebar.dc.html`): places, divider, course circles with the active stripe,
/// help and the avatar at the bottom.
struct Rail: View {
    let content: RailContent
    var onSelect: (String) -> Void = { _ in }
    /// Present in the app window (not in shell-only gallery screens): gives circles the course menu.
    @Environment(Workspace.self) private var workspace: Workspace?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(RailContent.Place.allCases, id: \.self) { place in
                RailPlaceButton(
                    glyph: RailGlyph(rawValue: place.rawValue) ?? .home,
                    isOn: content.active == place.rawValue,
                    hasDot: place == .inbox && content.inboxHasItems
                ) { onSelect(place.rawValue) }
                .marginTooltip(place.title, shortcut: place.shortcut.isEmpty ? nil : place.shortcut, placement: .trailing)
                .accessibilityLabel(place.title)
                .contextMenu {
                    if let workspace {
                        Button("Open") { workspace.railSelect(place.rawValue) }
                        Button("Open in new tab") { workspace.railSelect(place.rawValue, newTab: true) }
                    }
                }
            }
            MarginDivider(color: MarginColor.border).frame(width: 24).padding(.vertical, 6)
            ForEach(content.courses, id: \.id) { course in
                let on = content.active == course.id
                Button { onSelect(course.id) } label: {
                    CourseCircle(style: course.style)
                        .overlay {
                            if on {
                                Circle().strokeBorder(MarginColor.sidebar, lineWidth: 2).padding(-2)
                                Circle().strokeBorder(Color(hexString: course.style.foreground), lineWidth: 2).padding(-4)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .overlay(alignment: .leading) {
                            if on {
                                UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3)
                                    .fill(MarginColor.ink)
                                    .frame(width: 4, height: 20)
                                    .offset(x: -8)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(course.name)
                .modifier(CourseHoverCardModifier(courseID: course.id, name: course.name, workspace: workspace))
                .contextMenu {
                    if let workspace, let c = workspace.courses.course(id: course.id) {
                        CourseMenuItems(course: c).environment(workspace)
                    }
                }
            }
            Spacer(minLength: 0)
            RailIcon(glyph: .help)
                .frame(width: 40, height: 40)
            AccountButton(initials: content.initials)
        }
        .padding(.top, 52)
        .padding(.bottom, 14)
        .frame(width: 56)
    }
}

/// 3e on rail circles: name, code, next class, next exam, open tasks.
private struct CourseHoverCardModifier: ViewModifier {
    let courseID: String
    let name: String
    let workspace: Workspace?

    func body(content: Content) -> some View {
        if let workspace, let card = workspace.courses.cards.first(where: { $0.id == courseID }) {
            content.marginHoverCard(placement: .trailing) { CourseHoverCard(card: card, openTasks: workspace.courses.openTasks(of: courseID), today: workspace.env.clock.today) }
        } else {
            content.marginTooltip(name, shortcut: nil, placement: .trailing)
        }
    }
}

struct CourseHoverCard: View {
    let card: CourseCardData
    let openTasks: Int
    let today: LocalDate

    var body: some View {
        HoverCardSurface {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.course.name).font(.margin(16, .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Text(card.course.code).font(.margin(12)).foregroundStyle(MarginColor.textTertiary)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let next = card.next {
                    // „Tue 10:00 · Lecture 9 · Membrane transport“ → „Lecture 9“, „Tue 10:00 · Sci 204“.
                    let parts = next.components(separatedBy: " · ")
                    line("event", parts.count > 1 ? parts[1] : "Next class",
                         [parts.first, card.course.room].compactMap { $0 }.joined(separator: " · "))
                }
                if let exam = card.course.exams.filter({ $0.date >= today }).min(by: { $0.date < $1.date }) {
                    line("quiz", exam.title, CourseDetailModel.day(exam.date))
                }
                line("check_box_outline_blank", openTasks == 1 ? "1 open task" : "\(openTasks) open tasks", nil)
                if let grade = card.grade { line("bar_chart", "Grade so far", grade) }
            }
        }
    }

    private func line(_ icon: String, _ title: String, _ meta: String?) -> some View {
        HStack(spacing: 8) {
            Icon(icon, size: 16, color: MarginColor.textSecondary)
            Text(title).font(.margin(13)).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            if let meta { Text(meta).font(.margin(13)).foregroundStyle(MarginColor.textSecondary).fixedSize() }
        }
    }
}

private struct RailPlaceButton: View {
    let glyph: RailGlyph
    let isOn: Bool
    let hasDot: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            // Margin's own rail icons: outlined, solid black when selected (user's call).
            RailIcon(glyph: glyph, filled: isOn)
                .frame(width: 40, height: 40)
                .background(isOn ? MarginColor.borderSubtle : (hovered ? MarginColor.hover : .clear),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if hasDot {
                        Circle().fill(MarginColor.accent)
                            .frame(width: 7, height: 7)
                            .overlay { Circle().stroke(MarginColor.sidebar, lineWidth: 1.5) }
                            .padding(6)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
