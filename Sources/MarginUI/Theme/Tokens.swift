import SwiftUI

// Design tokens from `docs/design/mockups/margin-tokens.css` (source of truth, `00-overview.md` §2).
// Names are semantic so a dark palette can be added later without touching components.

/// Raw palette. Components should prefer `MarginColor`; this exists so tests can compare hex values.
public enum MarginPalette {
    public static let gray0: UInt32 = 0xFFFFFF
    public static let gray50: UInt32 = 0xF6F6F8
    public static let gray100: UInt32 = 0xF3F4F6
    public static let gray200: UInt32 = 0xE9EAEE
    public static let gray300: UInt32 = 0xDFE1E6
    public static let gray400: UInt32 = 0xC4C7CF
    public static let gray500: UInt32 = 0x9A9DA6
    public static let gray600: UInt32 = 0x686C78
    public static let gray900: UInt32 = 0x1C1E26

    public static let blue50: UInt32 = 0xE6EDFD
    public static let blue100: UInt32 = 0xCFDDFB
    public static let blue500: UInt32 = 0x2F6BEB
    public static let blue600: UInt32 = 0x2457D6
    public static let blue700: UInt32 = 0x1D47B3

    // Used across the mockups but not declared in margin-tokens.css.
    public static let hover: UInt32 = 0xF0F1F4
    public static let canvas: UInt32 = 0xE4E5E9
    public static let inspector: UInt32 = 0xFCFCFD
    public static let tabHover: UInt32 = 0xEDEEF1
    public static let red500: UInt32 = 0xD93F33
    public static let red50: UInt32 = 0xFCECEC
    public static let red600: UInt32 = 0xBE2E2E
    public static let green50: UInt32 = 0xE9F6EE
    public static let green600: UInt32 = 0x248049
    public static let amber50: UInt32 = 0xFBF2E1
    public static let amber600: UInt32 = 0xA66A07
}

public enum MarginColor {
    // Text
    public static let ink = Color(hex: MarginPalette.gray900)
    public static let textSecondary = Color(hex: MarginPalette.gray600)
    public static let textTertiary = Color(hex: MarginPalette.gray500)
    public static let textDisabled = Color(hex: MarginPalette.gray400)

    // Surfaces
    public static let surface = Color(hex: MarginPalette.gray0)
    public static let sidebar = Color(hex: MarginPalette.gray50)
    public static let sunken = Color(hex: MarginPalette.gray100)
    public static let hover = Color(hex: MarginPalette.hover)
    public static let canvas = Color(hex: MarginPalette.canvas)
    public static let inspector = Color(hex: MarginPalette.inspector)
    public static let tabHover = Color(hex: MarginPalette.tabHover)

    // Borders
    public static let border = Color(hex: MarginPalette.gray300)
    public static let borderSubtle = Color(hex: MarginPalette.gray200)
    public static let borderCard = Color(hex: MarginPalette.canvas)
    public static let borderStrong = Color(hex: MarginPalette.gray400)

    // Accent
    public static let accent = Color(hex: MarginPalette.blue500)
    public static let accentHover = Color(hex: MarginPalette.blue600)
    public static let accentPressed = Color(hex: MarginPalette.blue700)
    public static let accentSoft = Color(hex: MarginPalette.blue50)
    public static let accentRing = Color(hex: MarginPalette.blue100)
    /// Text on `accentSoft` (active nav item, selected chip).
    public static let accentText = Color(hex: MarginPalette.blue600)

    // Status
    public static let due = Color(hex: MarginPalette.red500)
    public static let dueSoft = Color(hex: MarginPalette.red50)
    public static let dangerText = Color(hex: MarginPalette.red600)
    public static let successSoft = Color(hex: MarginPalette.green50)
    public static let successText = Color(hex: MarginPalette.green600)
    public static let warningSoft = Color(hex: MarginPalette.amber50)
    public static let warningText = Color(hex: MarginPalette.amber600)
}

/// Type scale: 12 meta · 13 secondary · 15 UI · 17 editor · 20 titles · 30 page.
public enum MarginTextSize {
    public static let xs: CGFloat = 12
    public static let sm: CGFloat = 13
    public static let base: CGFloat = 15
    public static let md: CGFloat = 17
    public static let lg: CGFloat = 20
    public static let page: CGFloat = 30
    /// Default letter spacing (`--tracking`).
    public static let tracking: CGFloat = -0.2
}

public enum MarginRadius {
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let tile: CGFloat = 12
    public static let window: CGFloat = 14
    public static let dialog: CGFloat = 16
}

public struct MarginShadow: Sendable {
    public let opacity: Double
    public let radius: CGFloat
    public let y: CGFloat

    /// `0 12 40 rgba(28,30,38,.10)`
    public static let card = MarginShadow(opacity: 0.10, radius: 20, y: 12)
    /// `0 12 32 rgba(28,30,38,.16)`
    public static let popover = MarginShadow(opacity: 0.16, radius: 16, y: 12)
    /// `0 24 64 rgba(28,30,38,.24)`
    public static let modal = MarginShadow(opacity: 0.24, radius: 32, y: 24)
}

extension View {
    /// CSS blur radius is twice the SwiftUI shadow radius.
    public func marginShadow(_ shadow: MarginShadow) -> some View {
        self.shadow(color: MarginColor.ink.opacity(shadow.opacity), radius: shadow.radius, x: 0, y: shadow.y)
    }
}

extension Color {
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// `#RRGGBB` as stored in `CourseStyle`; invalid strings give neutral grey.
    public init(hexString: String) {
        let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        self.init(hex: digits.count == 6 ? UInt32(digits, radix: 16) ?? 0x9A9DA6 : 0x9A9DA6)
    }
}
