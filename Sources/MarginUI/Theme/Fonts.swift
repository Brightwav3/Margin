import AppKit
import CoreText
import Synchronization
import SwiftUI

/// Inter (variable, `wght` + `opsz`), bundled under `Resources/Fonts` with its OFL licence.
///
/// Fonts are registered for the process at first use, so the package works in the app, previews
/// and tests alike. Weight and optical size are set through variation axes, which matches the
/// browser rendering of the mockups (automatic optical sizing).
public enum MarginFonts {
    public static let family = "Inter"

    private static let registration: Bool = {
        let fonts = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        var ok = !fonts.isEmpty
        for url in fonts {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered (e.g. second bundle load) is fine; anything else is a failure.
                let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
                if code != CTFontManagerError.alreadyRegistered.rawValue { ok = false }
            }
        }
        return ok
    }()

    /// Registers the bundled fonts. Returns false when Inter could not be loaded.
    @discardableResult
    public static func register() -> Bool { registration }

    private static let wghtAxis = 0x7767_6874 // 'wght'
    private static let opszAxis = 0x6F70_737A // 'opsz'

    /// `NSFont` for Inter at a size and weight, optical size following the point size (14…32).
    public static func nsFont(size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> NSFont {
        ctFont(size: size, weight: weight, italic: italic) as NSFont
    }

    /// Falls back to the system font when Inter is missing, so text never disappears.
    public static func ctFont(size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> CTFont {
        register()
        let name = italic ? "Inter-Italic" : "Inter-Regular"
        let variations: [Int: CGFloat] = [
            wghtAxis: numericWeight(weight),
            opszAxis: min(max(size, 14), 32),
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: name,
            kCTFontVariationAttribute: variations as CFDictionary,
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        if CTFontCopyFamilyName(font) as String == family { return font }
        return NSFont.systemFont(ofSize: size, weight: nsWeight(weight)) as CTFont
    }

    /// Inter's `wght` value for a weight. Lighter than the CSS numbers of the mockups (by the
    /// user's call, like the ChatGPT app): 400 → 370, 500 → 460, 600 → 540, 700 → 620.
    static func numericWeight(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: 200
        case .thin: 100
        case .light: 300
        case .medium: 460
        case .semibold: 540
        case .bold: 620
        case .heavy: 760
        case .black: 860
        default: 370
        }
    }

    private static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .light: .light
        default: .regular
        }
    }
}

private struct FontKey: Hashable {
    let size: CGFloat
    let weight: CGFloat
    let italic: Bool
}

private let fontCache = Mutex<[FontKey: Font]>([:])

extension Font {
    /// Inter at a size from `MarginTextSize` and a weight (400/500/600/700 in the mockups).
    public static func margin(_ size: CGFloat, _ weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let key = FontKey(size: size, weight: MarginFonts.numericWeight(weight), italic: italic)
        if let cached = fontCache.withLock({ $0[key] }) { return cached }
        let font = Font(MarginFonts.ctFont(size: size, weight: weight, italic: italic))
        fontCache.withLock { $0[key] = font }
        return font
    }
}
