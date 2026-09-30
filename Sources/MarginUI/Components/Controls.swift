import SwiftUI

/// Filter chip: selected `#E6EDFD`/`#2457D6`, otherwise outlined. Height 34, radius 8.
/// `.compact` is the borderless 30 px variant from the Notes sidebar (All / Lectures / Tasks).
public struct FilterChip: View {
    public enum Style: Sendable { case outlined, compact }

    let title: String
    let isOn: Bool
    let style: Style
    let action: () -> Void
    @State private var hovered = false

    public init(_ title: String, isOn: Bool, style: Style = .outlined, action: @escaping () -> Void = {}) {
        self.title = title
        self.isOn = isOn
        self.style = style
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MarginRadius.sm)
        Button(action: action) {
            Text(title)
                .marginFont(style == .outlined ? MarginTextSize.base : 14)
                .lineLimit(1)
                .foregroundStyle(isOn ? MarginColor.accentText : MarginColor.ink)
                .padding(.horizontal, style == .outlined ? 16 : 10)
                .frame(height: style == .outlined ? 34 : 30)
                .background(background, in: shape)
                .overlay {
                    if style == .outlined, !isOn { shape.strokeBorder(MarginColor.border) }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var background: Color {
        if isOn { return MarginColor.accentSoft }
        return hovered ? MarginColor.hover : (style == .outlined ? MarginColor.surface : .clear)
    }
}

/// Small pill label (Fidelio `Badge`): 12/500, padding 2×8.
public struct Badge: View {
    public enum Tone: Sendable { case neutral, accent, success, warning, danger }

    let text: String
    let tone: Tone
    let dot: Bool

    public init(_ text: String, tone: Tone = .neutral, dot: Bool = false) {
        self.text = text
        self.tone = tone
        self.dot = dot
    }

    public var body: some View {
        HStack(spacing: 5) {
            if dot { Circle().fill(colors.fg).frame(width: 6, height: 6) }
            Text(text).marginFont(MarginTextSize.xs, .medium).lineLimit(1)
        }
        .foregroundStyle(colors.fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(colors.bg, in: Capsule())
    }

    private var colors: (bg: Color, fg: Color) {
        switch tone {
        case .neutral: (MarginColor.sunken, MarginColor.textSecondary)
        case .accent: (MarginColor.accentSoft, MarginColor.accentPressed)
        case .success: (MarginColor.successSoft, MarginColor.successText)
        case .warning: (MarginColor.warningSoft, MarginColor.warningText)
        case .danger: (MarginColor.dueSoft, MarginColor.dangerText)
        }
    }
}

/// 16 px checkbox: blue fill with a white tick when on, `#C4C7CF` border when off.
public struct CheckboxView: View {
    @Binding var isOn: Bool
    let size: CGFloat
    /// What VoiceOver reads („Problem set 4“); the row usually provides it.
    let label: String?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    public init(isOn: Binding<Bool>, size: CGFloat = 16, label: String? = nil) {
        _isOn = isOn
        self.size = size
        self.label = label
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28)
        Button { isOn.toggle() } label: {
            ZStack {
                shape.fill(isOn ? MarginColor.accent : MarginColor.surface)
                shape.strokeBorder(isOn ? MarginColor.accent : (hovered ? MarginColor.textTertiary : MarginColor.borderStrong))
                if isOn {
                    Path { p in
                        p.move(to: CGPoint(x: 0.24, y: 0.52))
                        p.addLine(to: CGPoint(x: 0.42, y: 0.70))
                        p.addLine(to: CGPoint(x: 0.76, y: 0.30))
                    }
                    .applying(CGAffineTransform(scaleX: size, y: size))
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: size, height: size)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isOn)
        .accessibilityLabel(label ?? "Done")
        .accessibilityValue(isOn ? "checked" : "unchecked")
        .accessibilityAddTraits(.isToggle)
    }
}

/// 36×20 switch with a 16 px thumb.
public struct SwitchView: View {
    @Binding var isOn: Bool
    let label: String?
    @Environment(\.isEnabled) private var isEnabled

    public init(isOn: Binding<Bool>, label: String? = nil) {
        _isOn = isOn
        self.label = label
    }

    public var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? MarginColor.accent : MarginColor.border)
                .frame(width: 36, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .frame(width: 16, height: 16)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.16), value: isOn)
        .accessibilityLabel(label ?? "Switch")
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Two or more segments in a sunken track (Task / Note in quick capture).
public struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    public init(_ options: [(value: Value, title: String)], selection: Binding<Value>) {
        self.options = options
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .marginFont(MarginTextSize.sm)
                        .foregroundStyle(on ? MarginColor.ink : MarginColor.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: MarginRadius.xs)
                                    .fill(MarginColor.surface)
                                    .shadow(color: MarginColor.ink.opacity(0.08), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        .animation(.easeOut(duration: 0.14), value: selection)
    }
}

/// Hairline separator, `#E9EAEE` by default.
public struct MarginDivider: View {
    let axis: Axis
    let color: Color

    public init(_ axis: Axis = .horizontal, color: Color = MarginColor.borderSubtle) {
        self.axis = axis
        self.color = color
    }

    public var body: some View {
        color.frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}
