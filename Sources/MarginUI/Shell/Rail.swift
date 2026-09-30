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
                    icon: place.icon,
                    isOn: content.active == place.rawValue,
                    hasDot: place == .inbox && content.inboxHasItems
                ) { onSelect(place.rawValue) }
                .help(place.rawValue.capitalized)
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
                .help(course.name)
                .contextMenu {
                    if let workspace, let c = workspace.courses.course(id: course.id) {
                        CourseMenuItems(course: c).environment(workspace)
                    }
                }
            }
            Spacer(minLength: 0)
            Icon("help", size: 22, color: MarginColor.textSecondary)
                .frame(width: 40, height: 40)
            Text(content.initials)
                .font(.margin(MarginTextSize.xs, .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(MarginColor.ink, in: Circle())
        }
        .padding(.top, 52)
        .padding(.bottom, 14)
        .frame(width: 56)
    }
}

private struct RailPlaceButton: View {
    let icon: String
    let isOn: Bool
    let hasDot: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 22, weight: isOn ? .bold : .regular,
                 color: isOn ? MarginColor.ink : MarginColor.textSecondary)
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
