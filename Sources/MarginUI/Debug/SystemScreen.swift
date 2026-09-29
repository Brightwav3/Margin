import MarginCore
import SwiftUI

/// The System section of `Margin.dc.html`: type, colours, course tiles and controls, plus the
/// rest of the M0 components, on the `#E4E5E9` canvas.
struct SystemScreen: View {
    @State private var checked = true
    @State private var unchecked = false
    @State private var switchOn = true
    @State private var switchOff = false
    @State private var kind = "task"
    @State private var chip = "All"

    private let courses = Fixtures.week5.courses

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(280), spacing: 20, alignment: .top), count: 4),
                          alignment: .leading, spacing: 20) {
                    panel("Type · Inter") { typeSamples }
                    panel("Neutrals and accent") { swatches }
                    panel("Course tiles") { tiles }
                    panel("Controls") { controls }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(280), spacing: 20, alignment: .top), count: 4),
                          alignment: .leading, spacing: 20) {
                    panel("Buttons · states") { buttonStates }
                    panel("Badges and toggles") { badges }
                    panel("Properties") { properties }
                    panel("Icons · Lucide \(LucideIcons.shared.version)") { icons }
                }
            }
            .padding(40)
        }
        .background(MarginColor.canvas)
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
            content()
        }
        .padding(20)
        .frame(width: 280, alignment: .leading)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.borderCard) }
    }

    private var typeSamples: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Page 30").font(.margin(MarginTextSize.page, .bold)).tracking(-0.6)
            Text("Title 20").marginFont(MarginTextSize.lg, .semibold)
            Text("Editor body 17").marginFont(MarginTextSize.md)
            Text("UI body 15").marginFont(MarginTextSize.base)
            Text("Secondary 13").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
            Text("Meta 12").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
        }
        .foregroundStyle(MarginColor.ink)
    }

    private var swatches: some View {
        let items: [(String, Color, Bool)] = [
            ("Ink", MarginColor.ink, false), ("Grey", MarginColor.textSecondary, false),
            ("Sidebar", MarginColor.sidebar, true), ("Sunken", MarginColor.sunken, false),
            ("Blue", MarginColor.accent, false), ("Blue soft", MarginColor.accentSoft, false),
            ("Border", MarginColor.border, false), ("Due", MarginColor.due, false),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(items, id: \.0) { name, color, outlined in
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: MarginRadius.sm)
                        .fill(color)
                        .frame(height: 40)
                        .overlay {
                            if outlined { RoundedRectangle(cornerRadius: MarginRadius.sm).strokeBorder(MarginColor.borderCard) }
                        }
                    Text(name).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textSecondary)
                }
            }
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(courses) { course in
                VStack(spacing: 6) {
                    CourseTile(style: course.style)
                    Text(course.code).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textSecondary)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                MarginButton("New course", icon: "add", kind: .primary)
                MarginButton("Sort", trailingIcon: "expand_more")
            }
            HStack(spacing: 8) {
                FilterChip("All", isOn: chip == "All") { chip = "All" }
                FilterChip("Sciences", isOn: chip == "Sciences") { chip = "Sciences" }
            }
            HStack(spacing: 12) {
                CheckboxView(isOn: $unchecked)
                CheckboxView(isOn: $checked)
                Badge("Exam", tone: .danger)
                Badge("Due Fri", tone: .warning)
            }
        }
    }

    private var buttonStates: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MarginButton("Primary", kind: .primary)
                MarginButton("Disabled", kind: .primary).disabled(true)
            }
            HStack(spacing: 8) {
                MarginButton("Secondary")
                MarginButton("Off").disabled(true)
            }
            HStack(spacing: 8) {
                MarginButton(icon: "search", kind: .icon)
                MarginButton(icon: "more_horiz", kind: .icon)
                MarginButton("Inbox", kind: .primary, size: .small)
            }
        }
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Badge("Neutral")
                Badge("Accent", tone: .accent)
                Badge("Done", tone: .success, dot: true)
            }
            HStack(spacing: 12) {
                SwitchView(isOn: $switchOff)
                SwitchView(isOn: $switchOn)
            }
            Segmented([(value: "task", title: "Task"), (value: "note", title: "Note")], selection: $kind)
            HStack(spacing: 4) {
                FilterChip("All", isOn: true, style: .compact)
                FilterChip("Lectures", isOn: false, style: .compact)
                FilterChip("Tasks", isOn: false, style: .compact)
            }
        }
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 0) {
            PropertyRow(icon: "calendar_today", key: "date", labelWidth: 100) { Text("24.09.2026").monospacedDigit() }
            PropertyRow(icon: "notes", key: "class", labelWidth: 100) {
                Text("Cell Biology").foregroundStyle(MarginColor.accent).underline()
            }
            PropertyRow(icon: "sell", key: "tags", labelWidth: 100) {
                HStack(spacing: 6) { PropertyTag("membranes") }
            }
            MarginDivider().padding(.vertical, 8)
            Card(padding: 12, interactive: true) {
                Text("Interactive card").marginFont(MarginTextSize.sm).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icons: some View {
        let names = ["home", "inbox", "light_mode", "calendar_today", "eco", "science", "change_history",
                     "account_balance", "trending_up", "psychology", "search", "add", "auto_awesome",
                     "description", "schedule", "push_pin", "share", "folder", "picture_as_pdf", "bolt"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 12) {
            ForEach(names, id: \.self) { Icon($0, size: 22, color: MarginColor.ink).help($0) }
        }
    }
}
