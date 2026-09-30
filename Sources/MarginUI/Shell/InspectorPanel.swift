import SwiftUI

/// Right panel, 300 px, `#FCFCFD` with a left border (`Inspector.dc.html`). Tab icons live in
/// the title bar; this view shows the selected tab's title and body.
struct InspectorPanel: View {
    @Bindable var model: AppModel
    let content: InspectorContent

    private var tab: InspectorTab {
        content.tabs.contains(model.inspectorTab) ? model.inspectorTab : .agent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.titles[tab] ?? tab.label)
                .marginFont(MarginTextSize.sm, .semibold)
                .foregroundStyle(MarginColor.textSecondary)
                .padding(EdgeInsets(top: 16, leading: 18, bottom: 6, trailing: 18))
            if tab == .agent {
                AgentTab(content: content)
            } else if let rows = content.rows[tab], !rows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(rows) { InspectorRowView(row: $0) }
                    }
                    .padding(.horizontal, 10)
                }
                .scrollIndicators(.never)
            } else {
                // Placeholder for tabs whose data is not wired yet.
                Text("Nothing here yet")
                    .marginFont(MarginTextSize.sm)
                    .foregroundStyle(MarginColor.textTertiary)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .frame(width: model.inspectorWidth ?? Shell.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(MarginColor.inspector)
        .overlay(alignment: .leading) { MarginDivider(.vertical) }
        .overlay(alignment: .leading) {
            ResizeHandle(edge: .leading, width: model.inspectorWidth ?? Shell.inspectorWidth,
                         onChange: { model.setInspectorWidth($0) },
                         onReset: { model.setInspectorWidth(nil) })
        }
        .foregroundStyle(MarginColor.ink)
    }
}

private struct InspectorRowView: View {
    let row: InspectorRow
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let icon = row.icon {
                Icon(icon, size: 18, color: MarginColor.textSecondary).padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .marginFont(14, row.isBold ? .semibold : .regular)
                    .foregroundStyle(row.isLink ? MarginColor.accentText : MarginColor.ink)
                if let meta = row.meta {
                    Text(meta)
                        .marginFont(MarginTextSize.xs)
                        .foregroundStyle(MarginColor.textTertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.count).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary).padding(.top, 2)
        }
        .padding(EdgeInsets(top: 7, leading: row.indent, bottom: 7, trailing: 8))
        .background(hovered ? MarginColor.hover : .clear, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        .onHover { hovered = $0 }
    }
}

/// Agent tab: context chip, chat, suggestions and the composer (UI only; MA3 wires the agent).
private struct AgentTab: View {
    let content: InspectorContent

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Icon(content.agentContext.icon, size: 14)
                        Text(content.agentContext.text).marginFont(MarginTextSize.xs)
                    }
                    .foregroundStyle(MarginColor.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MarginColor.hover, in: RoundedRectangle(cornerRadius: MarginRadius.xs))

                    ForEach(Array(content.chat.enumerated()), id: \.offset) { _, message in
                        Text(message.text)
                            .marginFont(14)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(message.fromUser ? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12) : EdgeInsets())
                            .background(message.fromUser ? MarginColor.accentSoft : .clear,
                                        in: RoundedRectangle(cornerRadius: MarginRadius.md))
                            .frame(maxWidth: message.fromUser ? 230 : .infinity,
                                   alignment: message.fromUser ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
                    }

                    VStack(spacing: 6) {
                        ForEach(Array(content.suggestions.enumerated()), id: \.offset) { _, s in
                            SuggestionRow(icon: s.icon, text: s.text)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)

            VStack(alignment: .leading, spacing: 10) {
                Text(content.placeholder).marginFont(14).foregroundStyle(MarginColor.textTertiary)
                HStack(spacing: 10) {
                    Icon("alternate_email", size: 18)
                    Icon("attach_file", size: 18)
                    Spacer(minLength: 0)
                    Circle().fill(MarginColor.accent).frame(width: 28, height: 28)
                        .overlay { Icon("arrow_upward", size: 16, weight: .bold, color: .white) }
                }
                .foregroundStyle(MarginColor.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
            .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.border) }
            .padding(12)
        }
    }
}

private struct SuggestionRow: View {
    let icon: String
    let text: String
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Icon(icon, size: 16, color: MarginColor.textSecondary)
            Text(text).marginFont(MarginTextSize.sm)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: MarginRadius.sm)
                .strokeBorder(hovered ? MarginColor.borderStrong : MarginColor.borderCard)
        }
        .onHover { hovered = $0 }
    }
}
