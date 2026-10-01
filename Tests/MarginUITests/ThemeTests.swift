import CoreText
import Foundation
import SwiftUI
import Testing
@testable import MarginUI

/// Repository root, for reading the mockups the tokens and icons are checked against.
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let mockups = repoRoot.appendingPathComponent("docs/design/mockups")

@Suite struct TokenTests {
    @Test func paletteMatchesMarginTokensCSS() throws {
        let css = try String(contentsOf: mockups.appendingPathComponent("margin-tokens.css"), encoding: .utf8)
        let regex = /--([a-z]+-\d+):\s*#([0-9A-Fa-f]{6})/
        var declared: [String: UInt32] = [:]
        for match in css.matches(of: regex) {
            declared[String(match.1)] = UInt32(match.2, radix: 16)
        }
        let swift: [String: UInt32] = [
            "gray-0": MarginPalette.gray0, "gray-50": MarginPalette.gray50, "gray-100": MarginPalette.gray100,
            "gray-200": MarginPalette.gray200, "gray-300": MarginPalette.gray300, "gray-400": MarginPalette.gray400,
            "gray-500": MarginPalette.gray500, "gray-600": MarginPalette.gray600, "gray-900": MarginPalette.gray900,
            "blue-50": MarginPalette.blue50, "blue-100": MarginPalette.blue100, "blue-500": MarginPalette.blue500,
            "blue-600": MarginPalette.blue600, "blue-700": MarginPalette.blue700,
        ]
        #expect(declared.count == swift.count, "margin-tokens.css declares \(declared.keys.sorted())")
        for (name, hex) in declared {
            #expect(swift[name] == hex, "\(name): css #\(String(hex, radix: 16)) vs swift")
        }
    }

    @Test func typeScaleAndRadiiMatchCSS() throws {
        let css = try String(contentsOf: mockups.appendingPathComponent("margin-tokens.css"), encoding: .utf8)
        func px(_ name: String) -> CGFloat? {
            guard let m = css.firstMatch(of: try! Regex("--\(name):\\s*(-?[0-9.]+)px")) else { return nil }
            return CGFloat(Double(m.output[1].substring!)!)
        }
        #expect(px("text-xs") == MarginTextSize.xs)
        #expect(px("text-sm") == MarginTextSize.sm)
        #expect(px("text-base") == MarginTextSize.base)
        #expect(px("text-md") == MarginTextSize.md)
        #expect(px("text-lg") == MarginTextSize.lg)
        #expect(px("text-2xl") == MarginTextSize.page)
        #expect(px("tracking") == MarginTextSize.tracking)
        #expect(px("radius-xs") == MarginRadius.xs)
        #expect(px("radius-sm") == MarginRadius.sm)
        #expect(px("radius-md") == MarginRadius.md)
        #expect(px("radius-tile") == MarginRadius.tile)
    }
}

@Suite struct FontTests {
    @Test func interIsBundledAndRegistered() {
        #expect(MarginFonts.register())
        let font = MarginFonts.ctFont(size: 15)
        #expect(CTFontCopyFamilyName(font) as String == "Inter")
    }

    // Lighter than the mockups by the user's call (DEVIATIONS.md, 2026-09-30).
    @Test(arguments: [(Font.Weight.regular, 370.0), (.medium, 460), (.semibold, 540), (.bold, 620)])
    func weightIsAppliedThroughVariationAxis(weight: Font.Weight, expected: Double) {
        let font = MarginFonts.ctFont(size: 20, weight: weight)
        let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
        // CoreText omits axes left at their default (wght 400).
        #expect((variation[NSNumber(value: 0x7767_6874)]?.doubleValue ?? 400) == expected)
    }

    @Test func italicFaceIsAvailable() {
        let font = MarginFonts.ctFont(size: 17, italic: true)
        #expect(CTFontCopyFamilyName(font) as String == "Inter")
        #expect(CTFontGetSymbolicTraits(font).contains(.traitItalic))
    }
}

@Suite struct IconTests {
    @Test func wholeLucideSetIsBundled() {
        #expect(LucideIcons.shared.version == "1.49.0")
        #expect(LucideIcons.shared.names.count > 1800)
    }

    @Test func everyBundledIconParsesToAPath() {
        for name in LucideIcons.shared.names {
            let glyph = LucideIcons.shared.glyph(name)
            #expect(glyph?.stroke.isEmpty == false, "\(name) has no geometry")
            let box = glyph?.stroke.boundingRect ?? .null
            #expect(box.minX >= -1 && box.minY >= -1 && box.maxX <= 25 && box.maxY <= 25, "\(name) outside viewBox: \(box)")
        }
    }

    @Test func aliasesResolve() {
        #expect(LucideIcons.shared.canonicalName("trash-2") != nil)
        #expect(LucideIcons.shared.canonicalName("circle-help") != nil)
        #expect(LucideIcons.shared.canonicalName("no-such-icon") == nil)
    }

    /// M0-05: every icon name used in a mockup has a mapping (or a DEVIATIONS.md entry).
    @Test func everyMockupIconIsMapped() throws {
        let files = ["Margin.dc.html", "Margin-Screens.dc.html", "Sidebar.dc.html", "Inspector.dc.html",
                     "margin-popups.dc.html"].map { mockups.appendingPathComponent($0) }
        let patterns = [/name="([a-z_0-9]+)"/, /icon: ?'([a-z_0-9]+)'/]
        var used = Set<String>()
        for file in files {
            let html = try String(contentsOf: file, encoding: .utf8)
            for pattern in patterns {
                for match in html.matches(of: pattern) { used.insert(String(match.1)) }
            }
        }
        // `design_doc_mode` is a <meta name>, not an icon.
        used.remove("design_doc_mode")
        #expect(used.count > 60)
        for name in used.sorted() {
            #expect(MarginIcons.lucideName(for: name) != nil, "mockup icon \(name) has no Lucide mapping")
        }
        for (material, lucide) in MarginIcons.materialToLucide {
            #expect(LucideIcons.shared.canonicalName(lucide) != nil, "\(material) → \(lucide) is not in Lucide")
        }
    }
}

@Suite struct SVGPathTests {
    @Test func arcWithSweepGoesTheRightWay() {
        let path = SVGPath.parse("M0 0 A10 10 0 0 1 20 0")
        let box = path.boundingRect
        #expect(abs(box.minY + 10) < 0.01)
        #expect(abs(box.maxY) < 0.01)
        #expect(abs(box.width - 20) < 0.01)
    }

    @Test func compactArcFlagsAndNumbers() {
        // Flags glued to the next number and numbers glued by sign or dot.
        let path = SVGPath.parse("M0 0a10 10 0 0010 10l.5.5-1-1")
        #expect(abs((path.currentPoint?.x ?? 0) - 9.5) < 0.001)
        #expect(abs((path.currentPoint?.y ?? 0) - 9.5) < 0.001)
    }

    @Test func implicitLinetoAfterMoveAndRelativeCommands() {
        let path = SVGPath.parse("m2 2 4 0 0 4h-4z")
        #expect(path.boundingRect == CGRect(x: 2, y: 2, width: 4, height: 4))
    }

    @Test func smoothCurvesReflectControlPoint() {
        let path = SVGPath.parse("M0 0 C0 10 10 10 10 0 S20 -10 20 0")
        #expect(abs(path.boundingRect.minY + 7.5) < 0.01)
        #expect(abs(path.boundingRect.maxY - 7.5) < 0.01)
    }

    @Test func malformedInputDoesNotCrash() {
        #expect(SVGPath.parse("M1 1 L").boundingRect == CGRect(x: 1, y: 1, width: 0, height: 0))
        #expect(SVGPath.parse("garbage").isEmpty)
    }
}

@Suite struct CourseIconSuggesterTests {
    @Test(arguments: [("Quantum Physics", "atom"), ("Art History", "palette"), ("Climate Science", "earth"),
                      ("Microbiology", "leaf"), ("Spanish B1", "languages"), ("Underwater Basket Weaving", "graduation-cap")])
    func iconFollowsSubject(name: String, icon: String) {
        #expect(CourseIconSuggester.suggest(name: name, usedKeys: []).icon == icon)
    }

    @Test(arguments: [("Společnost ve filmu", "clapperboard"), ("Akademické psaní a dovednosti", "pen-line"),
                      ("Napoleonské války a zrod nové Evropy", "crown"), ("Úvod do mezinárodních vztahů", "globe"),
                      ("Základy evropské integrace", "euro"), ("Mikroekonomie 1", "chart-line")])
    func czechNamesGetAFittingIcon(name: String, icon: String) {
        let s = CourseIconSuggester.suggest(name: name, usedKeys: [])
        #expect(s.icon == icon)
        #expect(LucideIcons.shared.canonicalName(s.icon) != nil)
        #expect(!s.emoji.isEmpty && s.emoji.allSatisfy(Icon.isEmoji))
    }

    @Test func everySuggestedIconAndEmojiExists() {
        for subject in CourseIconSuggester.subjects {
            for icon in subject.icons { #expect(LucideIcons.shared.canonicalName(icon) != nil, "\(icon)") }
            for e in subject.emoji { #expect(Icon.isEmoji(e), "\(e)") }
        }
        for group in CourseIconSuggester.emojiGroups {
            for e in group.emoji { #expect(Icon.isEmoji(e), "\(group.title) \(e)") }
        }
        #expect(CourseIconSuggester.palette.count == 18)
        #expect(!Icon.isEmoji("chart-line") && Icon.isEmoji("🎬"))
    }

    @Test func colourIsFirstUnusedThenStable() {
        let used = Set(CourseIconSuggester.palette.prefix(6).map(\.id))
        #expect(CourseIconSuggester.suggest(name: "Anything", usedKeys: used).swatch.id == "teal")
        let all = Set(CourseIconSuggester.palette.map(\.id))
        let a = CourseIconSuggester.suggest(name: "Statistics II", usedKeys: all).swatch.id
        #expect(a == CourseIconSuggester.suggest(name: "Statistics II", usedKeys: all).swatch.id)
    }

    @Test func everySuggestedIconExists() {
        for subject in CourseIconSuggester.subjects {
            for icon in subject.icons {
                #expect(LucideIcons.shared.canonicalName(icon) != nil, "\(icon) missing")
            }
        }
    }
}
