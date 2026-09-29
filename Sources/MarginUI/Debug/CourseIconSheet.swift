import MarginCore
import SwiftUI

// Design sheet (proposal, not in the mockups): how a new course gets its colour and icon.
// HACK(ui): `CourseIconSuggester` lives here while the sheet is under review; once approved the
// rules move to MarginCore next to `CoursePalette` (a contract change, scope `api`).

/// Colour set of one palette key (light tint, text/icon colour, dot).
struct PaletteSwatch: Identifiable, Hashable {
    let id: String
    let name: String
    let background: UInt32
    let foreground: UInt32
    let dot: UInt32
    let proposed: Bool

    var style: (bg: Color, fg: Color, dot: Color) {
        (Color(hex: background), Color(hex: foreground), Color(hex: dot))
    }
}

enum CourseIconSuggester {
    /// The six mockup keys, then six proposed ones so a semester with more courses stays distinct.
    static let palette: [PaletteSwatch] = [
        .init(id: "bio", name: "Green", background: 0xD8EFD9, foreground: 0x2F7D3E, dot: 0x6FBF7A, proposed: false),
        .init(id: "chem", name: "Sage", background: 0xD9E7DC, foreground: 0x2F5D3A, dot: 0x7FA88A, proposed: false),
        .init(id: "math", name: "Blue", background: 0xD6E2FA, foreground: 0x274FA8, dot: 0x6E97EC, proposed: false),
        .init(id: "hist", name: "Amber", background: 0xFBE8C4, foreground: 0x8F5D0E, dot: 0xE8B85C, proposed: false),
        .init(id: "econ", name: "Violet", background: 0xE5DEF8, foreground: 0x5B41B0, dot: 0x9A86DE, proposed: false),
        .init(id: "phil", name: "Coral", background: 0xFADAD6, foreground: 0xB3372B, dot: 0xEC8A80, proposed: false),
        .init(id: "teal", name: "Teal", background: 0xD3EEEC, foreground: 0x1F6F6A, dot: 0x5DBDB5, proposed: true),
        .init(id: "orange", name: "Orange", background: 0xFDE3D2, foreground: 0xA4501A, dot: 0xF0A26E, proposed: true),
        .init(id: "pink", name: "Pink", background: 0xF8DCEB, foreground: 0xA33A74, dot: 0xE58BBE, proposed: true),
        .init(id: "sky", name: "Sky", background: 0xD5ECF7, foreground: 0x1E6A8F, dot: 0x6BB8DE, proposed: true),
        .init(id: "olive", name: "Olive", background: 0xE8EDD2, foreground: 0x5B6B1E, dot: 0xA9BA5E, proposed: true),
        .init(id: "slate", name: "Slate", background: 0xE1E5EC, foreground: 0x3F4C63, dot: 0x8D9AB0, proposed: true),
    ]

    /// Subject groups: keywords in the course name → icon candidates (first is the default).
    static let subjects: [(group: String, keywords: [String], icons: [String])] = [
        ("Arts & media", [" art", "music", "design", "film", "photo", "theat", "media"],
         ["palette", "music", "pen-tool", "camera", "drama"]),
        ("Biology & life", ["bio", "cell", "gene", "ecolog", "zoolog", "botan", "micro", "anatom"],
         ["leaf", "dna", "microscope", "sprout"]),
        ("Chemistry", ["chem", "organic", "molec", "polymer"], ["flask-conical", "test-tube", "atom"]),
        ("Physics & space", ["physic", "quantum", "mechanic", "astro", "optic", "electr"],
         ["atom", "orbit", "magnet", "telescope", "zap"]),
        ("Maths & stats", ["math", "algebra", "calculus", "geometr", "statist", "probab", "logic"],
         ["triangle", "sigma", "pi", "calculator", "infinity", "chart-line"]),
        ("Computing", ["comput", "program", "software", "network", "data", "algorithm", "ai "],
         ["code", "cpu", "circuit-board"]),
        ("History & law", ["histor", "europe", "ancient", "law", "politic", "civil"],
         ["landmark", "scroll", "gavel", "swords", "map"]),
        ("Economics & business", ["econ", "financ", "business", "market", "account", "manag"],
         ["trending-up", "coins", "briefcase", "scale"]),
        ("Mind & society", ["philos", "psych", "mind", "sociol", "ethic", "anthrop"],
         ["brain", "users", "sparkles", "scale"]),
        ("Languages & literature", ["language", "spanish", "french", "german", "english", "literat", "writing", "linguist"],
         ["languages", "book-open", "feather", "message-circle", "book-a"]),
        ("Health & medicine", ["medic", "health", "nurs", "pharma", "physiol"], ["stethoscope", "heart-pulse", "pill"]),
        ("Earth & environment", ["geo", "earth", "climate", "environ"], ["earth", "mountain", "globe"]),
    ]

    struct Suggestion {
        let group: String?
        let icon: String
        let alternatives: [String]
        let swatch: PaletteSwatch
    }

    /// Icon from the first subject whose keyword appears in the name; colour is the first key not
    /// used by other courses this semester, else a stable hash of the name.
    static func suggest(name: String, usedKeys: Set<String>) -> Suggestion {
        let lower = " " + name.lowercased() + " "
        let subject = subjects.first { s in s.keywords.contains { lower.contains($0) } }
        let icon = subject?.icons.first ?? "graduation-cap"
        let alternatives = Array((subject?.icons.dropFirst() ?? ["book-open", "sparkles", "bookmark"]).prefix(4))
        let swatch = palette.first { !usedKeys.contains($0.id) }
            ?? palette[Int(stableHash(name) % UInt64(palette.count))]
        return Suggestion(group: subject?.group, icon: icon, alternatives: alternatives, swatch: swatch)
    }

    /// FNV-1a, so the same name always gets the same colour (Swift's `hashValue` is seeded per run).
    static func stableHash(_ s: String) -> UInt64 {
        s.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}

/// Gallery screen `course-icons`.
struct CourseIconSheet: View {
    @State private var name = "Quantum Physics"
    @State private var pickedIcon: String?
    @State private var pickedKey: String?

    private let usedKeys = Set(Fixtures.week5.courses.map(\.style.color))
    private let examples = ["Microbiology", "Statistics II", "Spanish B1", "Computer Networks",
                            "Art History", "Public Health", "Climate Science", "Contract Law"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Course icons").font(.margin(MarginTextSize.page, .bold)).tracking(-0.6)
                    Text("Návrh: nový předmět dostane barvu a ikonu automaticky, uživatel je může změnit.")
                        .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
                }
                HStack(alignment: .top, spacing: 20) {
                    generator.frame(width: 520)
                    anatomy
                }
                paletteSection
                subjectsSection
            }
            .padding(40)
            .foregroundStyle(MarginColor.ink)
        }
        .background(MarginColor.canvas)
    }

    // MARK: Generator

    private var suggestion: CourseIconSuggester.Suggestion {
        CourseIconSuggester.suggest(name: name, usedKeys: usedKeys)
    }

    /// Examples added one after another, so each takes the next unused colour.
    private var exampleSuggestions: [(name: String, suggestion: CourseIconSuggester.Suggestion)] {
        var taken = usedKeys
        return examples.map { name in
            let s = CourseIconSuggester.suggest(name: name, usedKeys: taken)
            taken.insert(s.swatch.id)
            return (name, s)
        }
    }

    private var chosenIcon: String { pickedIcon ?? suggestion.icon }
    private var chosenSwatch: PaletteSwatch {
        CourseIconSuggester.palette.first { $0.id == pickedKey } ?? suggestion.swatch
    }

    private var generator: some View {
        sheetCard("Generator") {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Course name", text: $name)
                    .textFieldStyle(.plain)
                    .marginFont(MarginTextSize.base)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
                    .overlay { RoundedRectangle(cornerRadius: MarginRadius.sm).strokeBorder(MarginColor.border) }
                    .onChange(of: name) { pickedIcon = nil; pickedKey = nil }

                HStack(alignment: .top, spacing: 16) {
                    let s = chosenSwatch.style
                    CourseTile(icon: chosenIcon, background: s.bg, foreground: s.fg, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name.isEmpty ? "New course" : name).marginFont(MarginTextSize.md, .semibold)
                        Text(suggestion.group.map { "Matched: \($0)" } ?? "No match · default icon")
                            .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                        Text("Colour: \(chosenSwatch.name)\(pickedKey == nil ? " · first unused" : "")")
                            .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                    HStack(spacing: 8) {
                        ForEach([suggestion.icon] + suggestion.alternatives, id: \.self) { icon in
                            pickable(on: chosenIcon == icon) { pickedIcon = icon } content: {
                                Icon(icon, size: 22, color: chosenSwatch.style.fg)
                            }
                        }
                    }
                    Text("Colour").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                        .padding(.top, 4)
                    HStack(spacing: 8) {
                        ForEach(CourseIconSuggester.palette) { swatch in
                            Button { pickedKey = swatch.id } label: {
                                Circle().fill(swatch.style.bg)
                                    .overlay { Circle().fill(swatch.style.dot).padding(8) }
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if swatch.id == chosenSwatch.id {
                                            Circle().strokeBorder(swatch.style.fg, lineWidth: 2).padding(-4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(swatch.name)
                        }
                    }
                }

                MarginDivider()
                Text("Examples").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(exampleSuggestions, id: \.name) { example, s in
                        Button { name = example } label: {
                            VStack(spacing: 6) {
                                CourseTile(icon: s.icon, background: s.swatch.style.bg,
                                           foreground: s.swatch.style.fg, size: 40)
                                Text(example).marginFont(MarginTextSize.xs)
                                    .foregroundStyle(MarginColor.textSecondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func pickable<Content: View>(on: Bool, action: @escaping () -> Void,
                                         @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .frame(width: 40, height: 40)
                .background(on ? chosenSwatch.style.bg : MarginColor.surface,
                            in: RoundedRectangle(cornerRadius: MarginRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: MarginRadius.sm)
                        .strokeBorder(on ? chosenSwatch.style.fg.opacity(0.5) : MarginColor.border)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Anatomy

    private var anatomy: some View {
        let s = chosenSwatch.style
        return sheetCard("Anatomy · where the icon appears") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 22) {
                    labelled("Tile 56 · System") {
                        CourseTile(icon: chosenIcon, background: s.bg, foreground: s.fg, size: 56)
                    }
                    labelled("Card 52 + ring") {
                        ZStack(alignment: .top) {
                            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                                .fill(s.bg).frame(width: 96, height: 34)
                            CourseTile(icon: chosenIcon, background: s.bg, foreground: s.fg, size: 52)
                                .background {
                                    RoundedRectangle(cornerRadius: 15).fill(MarginColor.surface).padding(-3)
                                }
                                .padding(.top, 14)
                        }
                        .frame(width: 96, height: 72, alignment: .top)
                    }
                    labelled("List 40") {
                        CourseTile(icon: chosenIcon, background: s.bg, foreground: s.fg, size: 40)
                    }
                }
                HStack(alignment: .bottom, spacing: 22) {
                    labelled("Rail 36") {
                        Circle().fill(s.bg).frame(width: 36, height: 36)
                            .overlay { Icon(chosenIcon, size: 20, color: s.fg) }
                    }
                    labelled("Rail active") {
                        Circle().fill(s.bg).frame(width: 36, height: 36)
                            .overlay { Icon(chosenIcon, size: 20, color: s.fg) }
                            .padding(2).overlay { Circle().strokeBorder(s.fg, lineWidth: 2) }
                            .background(Circle().fill(MarginColor.sidebar))
                    }
                    labelled("Tab dot 7") { Circle().fill(s.dot).frame(width: 7, height: 7) }
                    labelled("Header dot 10") { Circle().fill(s.dot).frame(width: 10, height: 10) }
                }
                HStack(spacing: 8) {
                    Circle().fill(s.dot).frame(width: 7, height: 7)
                    Text(name.isEmpty ? "New course" : name).marginFont(MarginTextSize.sm)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(MarginColor.surface, in: UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9))
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9).stroke(MarginColor.borderSubtle)
                }
                Text("Pravidla: ikona je vždy Lucide v barvě fg na bg; tečka (dot) se používá, kde není místo na ikonu.")
                    .marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            content()
            Text(label).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
        }
    }

    // MARK: Palette and subjects

    private var paletteSection: some View {
        sheetCard("Palette · 6 from the mockup + 6 proposed") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 16) {
                ForEach(CourseIconSuggester.palette) { swatch in
                    let s = swatch.style
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 0) {
                            s.bg
                            s.fg
                            s.dot
                        }
                        .frame(height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: MarginRadius.sm))
                        HStack(spacing: 6) {
                            Text(swatch.name).marginFont(MarginTextSize.sm, .medium)
                            if swatch.proposed { Badge("proposed", tone: .accent) }
                        }
                        Text(String(format: "#%06X · #%06X · #%06X", swatch.background, swatch.foreground, swatch.dot))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MarginColor.textTertiary)
                    }
                }
            }
        }
    }

    private var subjectsSection: some View {
        sheetCard("Subjects → icons (first is the default)") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3),
                      spacing: 18) {
                ForEach(Array(CourseIconSuggester.subjects.enumerated()), id: \.offset) { index, subject in
                    let swatch = CourseIconSuggester.palette[index % CourseIconSuggester.palette.count].style
                    VStack(alignment: .leading, spacing: 8) {
                        Text(subject.group).marginFont(MarginTextSize.sm, .semibold)
                        HStack(spacing: 6) {
                            ForEach(subject.icons, id: \.self) { icon in
                                CourseTile(icon: icon, background: swatch.bg, foreground: swatch.fg, size: 36)
                                    .help(icon)
                            }
                        }
                        Text(subject.keywords.joined(separator: " · "))
                            .marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func sheetCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
        .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.borderCard) }
    }
}
