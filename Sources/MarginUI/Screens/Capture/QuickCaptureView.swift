import MarginCore
import SwiftUI

/// 5a Quick entry: the line with highlighted course and date, chips, Task/Note, and the save button.
/// Shown over the window (dimmed) and in the global panel (⌃⌥Space, from any app).
public struct QuickCaptureView: View {
    @Bindable var model: CaptureModel
    var showsHint = true
    @FocusState private var focused: Bool
    /// Caret at the end on open, so the highlighted text under the field stays visible.
    @State private var selection: TextSelection?

    public init(model: CaptureModel, showsHint: Bool = true) {
        self.model = model
        self.showsHint = showsHint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if model.kind == .task {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(MarginColor.borderStrong, lineWidth: 1.2)
                            .frame(width: 16, height: 16)
                    } else {
                        Icon("description", size: 18, color: MarginColor.textSecondary)
                    }
                }
                .padding(.top, 6)
                ZStack(alignment: .topLeading) {
                    // The highlighted copy sits under a transparent field with the same font.
                    Text(model.highlighted)
                        .font(.margin(20))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                    TextField("Read ch. 6 before wed for bio #reading", text: $model.text, selection: $selection, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.margin(20))
                        .lineSpacing(4)
                        .foregroundStyle(model.text.isEmpty ? MarginColor.textTertiary : .clear)
                        .focused($focused)
                        .onSubmit { Task { await model.save() } }
                }
            }
            chips
            if let error = model.error {
                Text(error).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.dangerText).padding(.leading, 30)
            }
            HStack(spacing: 12) {
                Segmented([(InboxKind.task, "Task"), (InboxKind.note, "Note")], selection: $model.kind)
                    .fixedSize()
                if showsHint {
                    Text("⌃⌥Space from anywhere").frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                Button("⌘↵ Inbox") { Task { await model.save(toInbox: true) } }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                MarginButton(model.primaryTitle, kind: .primary, size: .small) { Task { await model.save() } }
                    .disabled(model.saving)
            }
            .marginFont(MarginTextSize.sm)
            .foregroundStyle(MarginColor.textTertiary)
            .padding(.top, 14)
            .overlay(alignment: .top) { MarginDivider(color: MarginColor.hover) }
        }
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 16, trailing: 24))
        .frame(width: 620)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.dialog))
        .marginShadow(.modal)
        .onAppear {
            focused = true
            selection = TextSelection(insertionPoint: model.text.endIndex)
        }
        .onExitCommand { model.close() }
    }

    @ViewBuilder
    private var chips: some View {
        let d = model.draft
        let spans = Set(model.parsed.spans.map(\.kind))
        FlowLayout(spacing: 8) {
            if let course = model.course {
                chip(icon: course.style.icon, text: course.name, bg: Color(hexString: course.style.background),
                     fg: Color(hexString: course.style.foreground)) { model.dropped.insert(.course) }
            }
            if let due = d.due {
                chip(icon: "calendar_today", text: CourseDetailModel.day(due) + (model.parsed.dueTime.map { " \(CoursesFormat.hour($0))" } ?? ""),
                     bg: MarginColor.accentSoft, fg: MarginColor.accentText) { model.dropped.insert(.date) }
            }
            ForEach(d.tags, id: \.self) { tag in
                chip(icon: "sell", text: tag, bg: .clear, fg: MarginColor.textSecondary, border: true) { model.dropped.insert(.tag) }
            }
            if let note = model.attachment {
                chip(icon: "school", text: "Attach to \(CourseDetailModel.split(note).0)", bg: .clear,
                     fg: MarginColor.textSecondary, border: true, dashed: true) { model.dropped.insert(.attachment) }
            } else if spans.contains(.attachment) || model.parsed.lectureHint != nil {
                chip(icon: "school", text: "No matching lecture note", bg: .clear, fg: MarginColor.textTertiary, border: true, dashed: true) {}
            }
        }
        .padding(.leading, 30)
    }

    private func chip(icon: String, text: String, bg: Color, fg: Color, border: Bool = false, dashed: Bool = false,
                      remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Icon(icon, size: 15, color: fg)
            Text(text)
            Button(action: remove) { Icon("close", size: 12, color: fg.opacity(0.7)) }
                .buttonStyle(.plain)
                .help("Remove")
        }
        .marginFont(MarginTextSize.sm)
        .foregroundStyle(fg)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(bg, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        .overlay {
            if border {
                RoundedRectangle(cornerRadius: MarginRadius.sm)
                    .strokeBorder(MarginColor.border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : []))
            }
        }
    }
}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: subviews.isEmpty ? 0 : y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
