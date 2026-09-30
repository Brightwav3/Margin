import MarginCore
import SwiftUI

/// Gallery `menus/3`: tooltips and hover cards of Margin Menus 3a–3h drawn in place (M10-33).
struct MenusSheet: View {
    @State private var workspace = Workspace(env: .fixture())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Tooltips and hover cards").marginFont(MarginTextSize.page, .bold)
                HStack(alignment: .top, spacing: 40) {
                    sample("3a Label and shortcut") { TooltipBubble(title: "Search", shortcut: "⌘K") }
                    sample("3b With explanation") {
                        TooltipBubble(title: "Due Tue 29 Sep", detail: "Written in Lecture 8. Change the @date there, or right-click the task.")
                    }
                    sample("3c Full title") { TooltipBubble(title: "Lecture 12 — Enzyme kinetics and inhibition", detail: "Cell Biology · Thu 12 Nov") }
                    sample("3d Why disabled") { TooltipBubble(title: "Available after your last exam on Fri 18 Dec") }
                }
                HStack(alignment: .top, spacing: 40) {
                    sample("3e Course hover card") {
                        if let card = workspace.courses.cards.first {
                            CourseHoverCard(card: card, openTasks: workspace.courses.openTasks(of: card.id), today: workspace.env.clock.today)
                                .shadow(color: MarginColor.ink.opacity(0.16), radius: 16, y: 12)
                        }
                    }
                    sample("3f Onboarding tip") { EditorTipPreview() }
                    sample("3g Validation") {
                        HStack(spacing: 8) {
                            Icon("error", size: 15, color: .white)
                            Text("Score can’t be higher than 20").font(.margin(13)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color(hex: 0xC4362B), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                sample("3h Chart value") {
                    VStack(spacing: 8) {
                        TooltipBubble(title: "Problem set 1 · 19/20", detail: "95% · counts 5%")
                        GradeChart(grades: Fixtures.week5.grades.filter { $0.courseID == "bio" }).frame(width: 520)
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MarginColor.canvas)
        .task { await workspace.courses.load() }
    }

    private func sample<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
            content()
        }
    }
}

private struct EditorTipPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tip 1 of 3").font(.margin(12)).foregroundStyle(MarginColor.accentRing)
            Text(EditorTips.tips[0].title).font(.margin(15, .semibold)).foregroundStyle(.white)
            Text(EditorTips.tips[0].text).font(.margin(13)).foregroundStyle(MarginColor.accentSoft).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 270, alignment: .leading)
        .background(MarginColor.accent, in: RoundedRectangle(cornerRadius: 12))
    }
}
