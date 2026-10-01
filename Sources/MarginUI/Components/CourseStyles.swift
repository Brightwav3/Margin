import MarginCore
import SwiftUI

/// Colour set of one palette key (light tint, text/icon colour, dot).
struct PaletteSwatch: Identifiable, Hashable {
    let id: String
    let name: String
    let background: UInt32
    let foreground: UInt32
    let dot: UInt32
    /// Added after the mockups (the mockups have six colours).
    let proposed: Bool

    var style: (bg: Color, fg: Color, dot: Color) {
        (Color(hex: background), Color(hex: foreground), Color(hex: dot))
    }
}

/// How a course gets its colour and icon: suggestions from the course name, the palette, the icon
/// and emoji catalogues of the style picker.
enum CourseIconSuggester {
    private static let names: [String: String] = [
        "bio": "Green", "chem": "Sage", "math": "Blue", "hist": "Amber", "econ": "Violet", "phil": "Coral",
        "teal": "Teal", "orange": "Orange", "pink": "Pink", "sky": "Sky", "olive": "Olive", "slate": "Slate",
        "indigo": "Indigo", "rose": "Rose", "lime": "Lime", "cyan": "Cyan", "brown": "Brown", "gold": "Gold",
    ]

    /// The palette in picker order (`CoursePalette` holds the colours).
    static let palette: [PaletteSwatch] = CoursePalette.orderedKeys.enumerated().map { index, key in
        let s = CoursePalette.style(icon: "", color: key)
        func hex(_ h: String) -> UInt32 { UInt32(h.dropFirst(), radix: 16) ?? 0 }
        return PaletteSwatch(id: key, name: names[key] ?? key.capitalized, background: hex(s.background),
                             foreground: hex(s.foreground), dot: hex(s.dot), proposed: index >= 6)
    }

    /// Subject groups: keywords in the course name (English and Czech) → icons (first is the
    /// default) and emoji.
    static let subjects: [(group: String, keywords: [String], icons: [String], emoji: [String])] = [
        ("Arts & media", [" art", "music", "design", "film", "photo", "theat", "media", "umění", "hudb", "divadl", "kino"],
         ["palette", "clapperboard", "music", "camera", "drama"], ["🎬", "🎨", "🎵", "📷", "🎭"]),
        ("Biology & life", ["bio", "cell", "gene", "ecolog", "zoolog", "botan", "micro", "anatom", "buněč", "život"],
         ["leaf", "dna", "microscope", "sprout"], ["🌿", "🧬", "🔬", "🦠"]),
        ("Chemistry", ["chem", "organic", "molec", "polymer", "organick"], ["flask-conical", "test-tube", "atom"], ["⚗️", "🧪", "🧫"]),
        ("Physics & space", ["physic", "quantum", "mechanic", "astro", "optic", "electr", "fyzik", "kvant"],
         ["atom", "orbit", "magnet", "telescope", "zap"], ["⚛️", "🪐", "🔭", "⚡"]),
        ("Maths & stats", ["math", "algebra", "calculus", "geometr", "statist", "probab", "logic", "matemat", "logik"],
         ["triangle", "sigma", "pi", "calculator", "infinity", "chart-line"], ["📐", "➗", "🧮", "📊"]),
        ("Computing", ["comput", "program", "software", "network", "data", "algorithm", "ai ", "informat", "počítač", "síť"],
         ["code", "cpu", "circuit-board", "terminal"], ["💻", "🖥️", "🤖", "⌨️"]),
        ("War & military", ["war", "military", "napoleon", "válk", "vojen", "armád", "bitv"],
         ["swords", "shield", "crown", "castle", "flag"], ["⚔️", "🛡️", "👑", "🏰", "🎖️"]),
        ("Politics & international", ["politic", "international", "democra", "diplom", "polit", "mezinárod", "demokra", "vztah",
                                      "europ", "evrop", "integrac", "global", "union", "unie"],
         ["globe", "vote", "landmark", "euro", "flag", "handshake"], ["🌍", "🗳️", "🏛️", "🇪🇺", "🤝"]),
        ("History & law", ["histor", "ancient", "law", "civil", "dějin", "histori", "práv", "středověk"],
         ["landmark", "scroll", "gavel", "map", "hourglass"], ["📜", "🏛️", "⚖️", "🗺️", "⏳"]),
        ("Economics & business", ["econ", "financ", "business", "market", "account", "manag", "ekonom", "financ", "podnik", "účet"],
         ["chart-line", "trending-up", "coins", "briefcase", "scale"], ["📈", "💰", "💼", "🪙"]),
        ("Mind & society", ["philos", "psych", "mind", "sociol", "ethic", "anthrop", "society", "filozof", "psycholog", "společnost", "etik"],
         ["brain", "users", "sparkles", "scale"], ["🧠", "👥", "💭", "🤔"]),
        ("Languages & writing", ["language", "spanish", "french", "german", "english", "literat", "writing", "linguist", "rhetor",
                                 "ambiguity", "doublespeak", "jazyk", "psaní", "literatur", "angličt", "němčin", "rétorik", "akademick"],
         ["languages", "pen-line", "book-open", "feather", "message-square-quote"], ["✍️", "📚", "🗣️", "💬", "📝"]),
        ("Health & medicine", ["medic", "health", "nurs", "pharma", "physiol", "zdrav", "lékař"],
         ["stethoscope", "heart-pulse", "pill"], ["🩺", "❤️", "💊"]),
        ("Earth & environment", ["geo", "earth", "climate", "environ", "země", "klima", "prostředí"],
         ["earth", "mountain", "globe"], ["🌎", "⛰️", "🌱"]),
    ]

    /// What the icon grid shows before a search: every subject icon, then general study icons.
    static let studyIcons: [String] = {
        let extra = ["graduation-cap", "school", "book", "book-open", "book-marked", "library", "notebook", "notebook-pen",
                     "pencil", "pen-tool", "highlighter", "ruler", "backpack", "presentation", "lightbulb", "bookmark",
                     "clipboard-list", "calendar", "clock", "target", "trophy", "star", "heart", "flag", "map-pin", "compass",
                     "puzzle", "rocket", "sparkles", "flame", "music-2", "mic", "video", "image", "newspaper", "file-text",
                     "folder", "archive", "database", "server", "wifi", "smartphone", "monitor", "keyboard", "wrench",
                     "hammer", "cog", "building", "building-2", "church", "factory", "tree-pine", "sun", "moon", "cloud",
                     "droplet", "wind", "snowflake", "bug", "bird", "fish", "paw-print", "apple", "coffee", "utensils",
                     "dumbbell", "bike", "plane", "car", "train-front", "ship", "anchor", "mountain-snow", "tent", "medal"]
        var seen = Set<String>()
        return (subjects.flatMap(\.icons) + keywordIcons.map(\.icon) + extra)
            .filter { LucideIcons.shared.canonicalName($0) != nil && seen.insert($0).inserted }
    }()

    /// A broad emoji set for the picker, grouped.
    static let emojiGroups: [(title: String, emoji: [String])] = [
        ("Studium", ["📚", "📖", "📝", "✏️", "🖊️", "📓", "📒", "📎", "🎓", "🏫", "🧑‍🏫", "🗂️", "📌", "🔖", "💡", "🧾"]),
        ("Vědy", ["🔬", "🧬", "🧪", "⚗️", "🧫", "⚛️", "🔭", "🪐", "🌡️", "🧲", "⚡", "🌿", "🦠", "🧮", "📐", "📊"]),
        ("Společnost", ["🌍", "🗳️", "🏛️", "⚖️", "🤝", "🇪🇺", "🇨🇿", "🗺️", "📜", "👑", "⚔️", "🛡️", "🏰", "💰", "📈", "💼"]),
        ("Umění a jazyk", ["🎬", "🎨", "🎵", "🎭", "📷", "🎹", "🗣️", "💬", "✍️", "🖋️", "📰", "🎙️", "🎻", "🖼️", "📽️", "🎧"]),
        ("Mysl a tělo", ["🧠", "💭", "🤔", "❤️", "🩺", "💊", "🏃", "🧘", "🍎", "☕️", "🌙", "☀️", "⭐️", "🔥", "✨", "🎯"]),
        ("Technika", ["💻", "🖥️", "⌨️", "🤖", "📱", "🛰️", "⚙️", "🔧", "🧰", "🔌", "💾", "🧑‍💻", "📡", "🕹️", "🚀", "🏗️"]),
    ]

    /// Keywords precise enough for their own icon, checked before the subject groups.
    static let keywordIcons: [(keywords: [String], icon: String)] = [
        (["film", "kino", "cinema"], "clapperboard"),
        (["writing", "psaní", "akademick"], "pen-line"),
        (["ambiguity", "doublespeak", "rhetor", "rétorik"], "message-square-quote"),
        (["napoleon"], "crown"),
        (["military", "vojen", "armád"], "shield"),
        (["democra", "demokra", "election", "volb"], "vote"),
        (["europ", "evrop", "union", "unie"], "euro"),
        (["international", "mezinárod", "global"], "globe"),
        (["microecon", "mikroekonom", "macroecon", "makroekonom"], "chart-line"),
    ]

    struct Suggestion {
        let group: String?
        let icon: String
        let alternatives: [String]
        let emoji: [String]
        let swatch: PaletteSwatch
    }

    /// Icon from the first subject whose keyword appears in the name; colour is the first key not
    /// used by other courses this semester, else a stable hash of the name.
    static func suggest(name: String, usedKeys: Set<String>) -> Suggestion {
        let lower = " " + name.lowercased() + " "
        let subject = subjects.first { s in s.keywords.contains { lower.contains($0) } }
        let precise = keywordIcons.first { k in k.keywords.contains { lower.contains($0) } }?.icon
        let icon = precise ?? subject?.icons.first ?? "graduation-cap"
        let alternatives = Array(((subject?.icons ?? ["book-open", "sparkles", "bookmark"]).filter { $0 != icon }).prefix(5))
        let swatch = palette.first { !usedKeys.contains($0.id) }
            ?? palette[Int(stableHash(name) % UInt64(palette.count))]
        return Suggestion(group: subject?.group, icon: icon, alternatives: alternatives,
                          emoji: subject?.emoji ?? ["📚", "🎓", "📝"], swatch: swatch)
    }

    /// FNV-1a, so the same name always gets the same colour (Swift's `hashValue` is seeded per run).
    static func stableHash(_ s: String) -> UInt64 {
        s.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}

/// Colour, icon or emoji of a course: preview, 18 colours, a Lucide icon from the suggestions or
/// the whole set (search), or an emoji from the groups or typed in.
struct CourseStylePicker: View {
    let courseName: String
    @Binding var color: String
    @Binding var icon: String
    var usedKeys: Set<String> = []

    enum Kind: String, CaseIterable { case icon = "Icon", emoji = "Emoji" }
    @State private var kind: Kind = .icon
    @State private var query = ""
    @State private var typedEmoji = ""

    private var suggestion: CourseIconSuggester.Suggestion {
        CourseIconSuggester.suggest(name: courseName.isEmpty ? "Course" : courseName, usedKeys: usedKeys)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            colours
            Picker("", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .accessibilityLabel("Icon or emoji")
            switch kind {
            case .icon: icons
            case .emoji: emojis
            }
        }
        .onAppear { if Icon.isEmoji(icon) { kind = .emoji } }
    }

    private var colours: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 9), alignment: .leading, spacing: 8) {
            ForEach(CourseIconSuggester.palette) { swatch in
                let s = swatch.style
                Button { color = swatch.id } label: {
                    Circle().fill(s.bg)
                        .overlay { Circle().fill(s.dot).padding(6) }
                        .overlay { if swatch.id == color { Circle().strokeBorder(s.fg, lineWidth: 2) } }
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .marginTooltip(swatch.name)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(swatch.id == color ? .isSelected : [])
            }
        }
    }

    private var icons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if query.isEmpty {
                FieldLabel(text: suggestion.group.map { "Suggested · \($0)" } ?? "Suggested")
                grid(([suggestion.icon] + suggestion.alternatives).filter { LucideIcons.shared.canonicalName($0) != nil }, columns: 8)
            }
            HStack(spacing: 8) {
                Icon("search", size: 15, color: MarginColor.textTertiary)
                TextField("Search \(LucideIcons.shared.names.count) icons", text: $query)
                    .textFieldStyle(.plain).marginFont(MarginTextSize.base)
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                grid(searchResults, columns: 10)
            }
            .frame(height: 176)
        }
    }

    private var searchResults: [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let all = LucideIcons.shared.names
        guard !q.isEmpty else { return CourseIconSuggester.studyIcons }
        let words = q.split(separator: " ").map(String.init)
        return Array(all.filter { name in words.allSatisfy { name.contains($0) } }.prefix(300))
    }

    private func grid(_ names: [String], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: columns), alignment: .leading, spacing: 4) {
            ForEach(names, id: \.self) { name in
                let on = LucideIcons.shared.canonicalName(icon) == name || icon == name
                Button { icon = name } label: {
                    Icon(name, size: 18, color: on ? MarginColor.accentText : MarginColor.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(on ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .marginTooltip(name)
                .accessibilityLabel(name)
            }
        }
    }

    private var emojis: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Suggested")
            emojiRow(suggestion.emoji)
            HStack(spacing: 8) {
                TextField("Type or paste any emoji", text: $typedEmoji)
                    .textFieldStyle(.plain).marginFont(MarginTextSize.base)
                    .onChange(of: typedEmoji) { _, new in
                        if let last = new.last.map(String.init), Icon.isEmoji(last) { icon = last }
                    }
                MarginButton("Emoji & symbols") { NSApp.orderFrontCharacterPalette(nil) }
            }
            .padding(.leading, 10).frame(height: 32)
            .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(CourseIconSuggester.emojiGroups, id: \.title) { group in
                        FieldLabel(text: group.title)
                        emojiRow(group.emoji)
                    }
                }
            }
            .frame(height: 176)
        }
    }

    private func emojiRow(_ list: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 10), alignment: .leading, spacing: 4) {
            ForEach(list, id: \.self) { e in
                Button { icon = e } label: {
                    Text(e).font(.system(size: 20))
                        .frame(width: 34, height: 34)
                        .background(e == icon ? MarginColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(e)
            }
        }
    }
}

/// Gallery screen `course-style`: the picker on an icon and on an emoji.
struct CourseStyleSheet: View {
    @State private var a = (color: "teal", icon: "pen-line")
    @State private var b = (color: "pink", icon: "🎬")

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            card("Akademické psaní a dovednosti", color: $a.color, icon: $a.icon)
            card("Společnost ve filmu", color: $b.color, icon: $b.icon)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MarginColor.canvas)
    }

    private func card(_ name: String, color: Binding<String>, icon: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CourseTile(style: CoursePalette.style(icon: icon.wrappedValue, color: color.wrappedValue), size: 52)
                Text(name).marginFont(MarginTextSize.md, .semibold)
            }
            CourseStylePicker(courseName: name, color: color, icon: icon)
        }
        .padding(20)
        .frame(width: 440)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.dialog))
        .marginShadow(.modal)
    }
}
