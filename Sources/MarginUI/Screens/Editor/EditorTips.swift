import SwiftUI

/// 3f Onboarding tips in the editor: three blue cards, once per user (Skip ends them).
struct EditorTips: View {
    static let tips: [(title: String, text: String)] = [
        ("Link notes with [[", "Type two brackets to link another note. Links update when you rename or move it."),
        ("Type / for blocks", "Tasks, headings, tables and callouts. A task with @Fri shows up in Upcoming."),
        ("⌘K finds anything", "Notes, courses and commands. ⌘⇧Space captures a thought from any app."),
    ]
    /// Index of the next tip; `tips.count` = done. Kept per user in the app's defaults.
    @AppStorage("tips.editor.next") private var next = 0

    var body: some View {
        if next < Self.tips.count {
            let tip = Self.tips[next]
            VStack(alignment: .leading, spacing: 6) {
                Text("Tip \(next + 1) of \(Self.tips.count)").font(.margin(12)).foregroundStyle(MarginColor.accentRing)
                Text(tip.title).font(.margin(15, .semibold)).foregroundStyle(.white)
                Text(tip.text).font(.margin(13)).foregroundStyle(MarginColor.accentSoft).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Spacer()
                    Button("Skip") { next = Self.tips.count }
                        .buttonStyle(.plain).font(.margin(13)).foregroundStyle(MarginColor.accentSoft)
                        .padding(.horizontal, 10).frame(height: 30)
                    Button(next + 1 == Self.tips.count ? "Done" : "Next") { next += 1 }
                        .buttonStyle(.plain).font(.margin(13, .medium)).foregroundStyle(MarginColor.accentText)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(.white, in: RoundedRectangle(cornerRadius: 7))
                }
                .padding(.top, 6)
            }
            .padding(14)
            .frame(width: 270, alignment: .leading)
            .background(MarginColor.accent, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: MarginColor.accentText.opacity(0.3), radius: 16, y: 12)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tip: \(tip.title)")
        }
    }
}
