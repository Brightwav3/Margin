import MarginCore
import SwiftUI

/// Course card of 1a (`Margin.dc.html`): 92 px banner in the course colour, 52 px tile with a
/// 3 px white ring overlapping the banner by 34 px, name 17/600, „14 notes · A−“, `…` menu and
/// the next class with a clock icon. Selected cards get the 1.5 px blue border.
struct CourseCard: View {
    let data: CourseCardData
    var isSelected = false
    var onOpen: () -> Void = {}

    var body: some View {
        let style = data.course.style
        Card(padding: 0, interactive: true, selected: isSelected) {
            VStack(alignment: .leading, spacing: 0) {
                // Banner image (M3-05) will fill this slot; until then the course colour.
                Color(hexString: style.background)
                    .frame(height: 92)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        CourseTile(style: style, size: 52)
                            .overlay {
                                RoundedRectangle(cornerRadius: MarginRadius.tile)
                                    .inset(by: -1.5)
                                    .stroke(MarginColor.surface, lineWidth: 3)
                            }
                            .padding(.top, -34)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(data.course.name)
                                .marginFont(MarginTextSize.md, .semibold)
                                .tracking(-0.3)
                                .lineSpacing(17 * 0.25 - 2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(data.summary)
                                .marginFont(MarginTextSize.base)
                                .foregroundStyle(MarginColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        CourseCardMenu(course: data.course, onOpen: onOpen)
                    }
                    .padding(.top, 12)

                    HStack(spacing: 8) {
                        Icon("schedule", size: 16, color: MarginColor.textTertiary)
                        Text(data.next ?? "No upcoming classes")
                            .marginFont(MarginTextSize.sm)
                            .foregroundStyle(MarginColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding([.horizontal, .bottom], 16)
            }
            // Cards in a row share the tallest height, like CSS grid `align-items: stretch`.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onTapGesture(perform: onOpen)
        .contextMenu { CourseMenuItems(course: data.course) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open", onOpen)
        .accessibilityIdentifier("course-card-\(data.id)")
    }
}

/// `more_horiz` menu of a card. Only Open works now; the rest arrive with the course popups (M10b 2f).
private struct CourseCardMenu: View {
    let course: Course
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        Menu {
            CourseMenuItems(course: course)
        } label: {
            Icon("more_horiz", size: 20, color: hovered ? MarginColor.ink : MarginColor.textSecondary)
                .frame(width: 24, height: 24)
                .background(hovered ? MarginColor.hover : .clear, in: RoundedRectangle(cornerRadius: MarginRadius.xs))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
        .accessibilityLabel("More actions for \(course.name)")
    }
}
