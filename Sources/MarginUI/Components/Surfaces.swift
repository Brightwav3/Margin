import MarginCore
import SwiftUI

/// White card, 1 px `#E4E5E9` border, radius 12. Interactive cards lift slightly on hover.
public struct Card<Content: View>: View {
    let padding: CGFloat
    let interactive: Bool
    let selected: Bool
    let content: Content
    @State private var hovered = false

    public init(padding: CGFloat = 16, interactive: Bool = false, selected: Bool = false,
                @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.interactive = interactive
        self.selected = selected
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MarginRadius.md)
        content
            .padding(padding)
            .background(MarginColor.surface)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    selected ? MarginColor.accent : (interactive && hovered ? MarginColor.border : MarginColor.borderCard),
                    lineWidth: selected ? 1.5 : 1
                )
            }
            .shadow(color: MarginColor.ink.opacity(interactive && hovered ? 0.06 : 0), radius: 8, y: 4)
            .offset(y: interactive && hovered ? -1 : 0)
            .contentShape(shape)
            .onHover { hovered = interactive && $0 }
            .animation(.easeOut(duration: 0.14), value: hovered)
    }
}

/// Pastel course tile with the course icon (56 px in System, 52 on cards, 40 in lists).
public struct CourseTile: View {
    let icon: String
    let background: Color
    let foreground: Color
    let size: CGFloat

    public init(icon: String, background: Color, foreground: Color, size: CGFloat = 56) {
        self.icon = icon
        self.background = background
        self.foreground = foreground
        self.size = size
    }

    public init(style: CourseStyle, size: CGFloat = 56) {
        self.init(icon: style.icon, background: Color(hexString: style.background),
                  foreground: Color(hexString: style.foreground), size: size)
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: MarginRadius.tile)
            .fill(background)
            .frame(width: size, height: size)
            .overlay { Icon(icon, size: size / 2, color: foreground) }
    }
}

/// Round course marker used in the rail (36 px) and the space switcher.
public struct CourseCircle: View {
    let style: CourseStyle
    let size: CGFloat

    public init(style: CourseStyle, size: CGFloat = 36) {
        self.style = style
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(Color(hexString: style.background))
            .frame(width: size, height: size)
            .overlay { Icon(style.icon, size: size * 0.56, color: Color(hexString: style.foreground)) }
    }
}

/// Property row of the note header: 160 px label column (narrower in tight panels) (icon + key), value on the right.
public struct PropertyRow<Value: View>: View {
    let icon: String
    let key: String
    let labelWidth: CGFloat
    let value: Value

    public init(icon: String, key: String, labelWidth: CGFloat = 160, @ViewBuilder value: () -> Value) {
        self.icon = icon
        self.key = key
        self.labelWidth = labelWidth
        self.value = value()
    }

    public var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Icon(icon, size: 18, color: MarginColor.textSecondary)
                Text(key).foregroundStyle(MarginColor.textSecondary)
            }
            .frame(width: labelWidth, alignment: .leading)
            value
                .foregroundStyle(MarginColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .marginFont(MarginTextSize.base)
        .frame(minHeight: 32)
    }
}

/// Tag pill inside a property value (`membranes`, `midterm`).
public struct PropertyTag: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .marginFont(MarginTextSize.sm)
            .foregroundStyle(MarginColor.accentText)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(MarginColor.accentSoft, in: RoundedRectangle(cornerRadius: 12))
    }
}
