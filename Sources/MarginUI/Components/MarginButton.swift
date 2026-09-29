import SwiftUI

extension View {
    /// Inter at a scale size with the default tracking (−0.2 pt).
    public func marginFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        font(.margin(size, weight)).tracking(MarginTextSize.tracking)
    }
}

/// Buttons from the System section of `Margin.dc.html`: primary (blue), secondary (outlined),
/// icon (ghost, square). Height 40, radius 8, text 15; `.small` is the 34 px footer variant.
public struct MarginButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, secondary, icon }
    public enum Size: Sendable { case regular, small }

    let kind: Kind
    let size: Size

    public init(_ kind: Kind = .secondary, size: Size = .regular) {
        self.kind = kind
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, size: size)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let kind: Kind
        let size: Size
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovered = false

        private var height: CGFloat { size == .regular ? 40 : 34 }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: MarginRadius.sm)
            configuration.label
                .marginFont(MarginTextSize.base, kind == .primary ? .medium : .regular)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .icon ? 0 : 14)
                .frame(minWidth: kind == .icon ? height : nil, minHeight: height, maxHeight: height)
                .background(background, in: shape)
                .overlay {
                    if kind == .secondary { shape.strokeBorder(MarginColor.border) }
                }
                .overlay {
                    if isFocused { shape.inset(by: -3).strokeBorder(MarginColor.accentRing, lineWidth: 3) }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovered = $0 && isEnabled }
                .animation(.easeOut(duration: 0.12), value: hovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .primary: .white
            case .secondary: MarginColor.ink
            case .icon: hovered ? MarginColor.ink : MarginColor.textSecondary
            }
        }

        private var background: Color {
            let pressed = configuration.isPressed && isEnabled
            switch kind {
            case .primary:
                return pressed ? MarginColor.accentPressed : hovered ? MarginColor.accentHover : MarginColor.accent
            case .secondary:
                return pressed ? MarginColor.borderSubtle : hovered ? MarginColor.sunken : MarginColor.surface
            case .icon:
                return pressed ? MarginColor.border : hovered ? MarginColor.borderSubtle : .clear
            }
        }
    }
}

/// Convenience button: optional leading icon, title, optional trailing icon (e.g. `expand_more`).
public struct MarginButton: View {
    let title: String?
    let icon: String?
    let trailingIcon: String?
    let kind: MarginButtonStyle.Kind
    let size: MarginButtonStyle.Size
    let action: () -> Void

    public init(
        _ title: String? = nil, icon: String? = nil, trailingIcon: String? = nil,
        kind: MarginButtonStyle.Kind = .secondary, size: MarginButtonStyle.Size = .regular,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.icon = icon
        self.trailingIcon = trailingIcon
        self.kind = kind
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Icon(icon, size: 20, color: kind == .secondary ? MarginColor.textSecondary : nil)
                }
                if let title { Text(title).lineLimit(1) }
                if let trailingIcon {
                    Icon(trailingIcon, size: 20, color: MarginColor.textSecondary)
                        .padding(.leading, -2)
                }
            }
            // Primary with an icon has a wider trailing inset (0 18 0 14), as in the mockup.
            .padding(.trailing, kind == .primary && icon != nil && title != nil ? 4 : 0)
        }
        .buttonStyle(MarginButtonStyle(kind, size: size))
        .accessibilityLabel(title ?? icon ?? "")
    }
}
