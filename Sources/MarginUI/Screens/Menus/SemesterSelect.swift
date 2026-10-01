import MarginCore
import SwiftUI

/// 2c Select field: the semester of a new course. The current one says so; archived semesters
/// are read-only, listed under their own header and not selectable.
struct SemesterSelect: View {
    let semesters: [Semester]
    let current: SemesterID?
    @Binding var selection: SemesterID?
    @State private var open = false

    private var selected: Semester? { semesters.first { $0.id == selection } }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Icon("school", size: 16, color: MarginColor.textSecondary)
                Text(selected?.name ?? "No semester").marginFont(MarginTextSize.base).foregroundStyle(MarginColor.ink)
                if let selected {
                    Text(Self.range(selected)).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                }
                Spacer(minLength: 4)
                Icon("expand_more", size: 16, color: MarginColor.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(width: 300, height: 42)
            .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(open ? MarginColor.accent : MarginColor.borderCard)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10).stroke(MarginColor.accentRing, lineWidth: 3).padding(-2).opacity(open ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
        .accessibilityLabel("Semester")
        .accessibilityValue(selected?.name ?? "None")
    }

    private var list: some View {
        let active = semesters.filter { !$0.isArchived }
        let archived = semesters.filter(\.isArchived)
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(active) { s in
                row(s, detail: Self.range(s) + (s.id == current ? " · current" : ""), enabled: true)
            }
            if !archived.isEmpty {
                MarginDivider(color: Color(hex: 0xEDEEF1)).padding(.vertical, 4)
                Text("Archived").marginFont(MarginTextSize.xs, .semibold).foregroundStyle(MarginColor.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                ForEach(archived) { s in row(s, detail: "Read-only", enabled: false) }
            }
        }
        .padding(5)
        .frame(width: 300)
    }

    private func row(_ s: Semester, detail: String, enabled: Bool) -> some View {
        Button {
            selection = s.id
            open = false
        } label: {
            HStack(spacing: 8) {
                Icon("check", size: 14, color: MarginColor.ink).frame(width: 16).opacity(s.id == selection ? 1 : 0)
                Text(s.name).frame(maxWidth: .infinity, alignment: .leading)
                Text(detail).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
            }
            .marginFont(14)
            .foregroundStyle(enabled ? MarginColor.ink : MarginColor.textDisabled)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .disabled(!enabled)
    }

    static func range(_ s: Semester) -> String {
        "\(CourseDetailModel.day(s.start)) – \(CourseDetailModel.day(s.end))"
    }
}

/// Hover background of a menu row for plain buttons.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Hovering(configuration.label) }

    private struct Hovering<Label: View>: View {
        let label: Label
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled
        init(_ label: Label) { self.label = label }
        var body: some View {
            label
                .background(hovered && enabled ? MarginColor.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .onHover { hovered = $0 }
        }
    }
}
