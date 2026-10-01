/// Maps the `color:` key of a `_course.md` to the course's colours (vault spec 05 §5).
///
/// The vault stores only the palette key; the tints are domain data shared by the fixture and the
/// vault implementation so a course looks the same from either. Unknown keys get a neutral grey
/// (the file stays valid, the app never fails on a hand-edited key).
public enum CoursePalette {
    /// The built-in keys in picker order: the six mockup colours, then twelve more so a full
    /// semester stays distinct. Each is a light tint, a foreground and a dot colour.
    static let ordered: [(key: String, background: String, foreground: String, dot: String)] = [
        ("bio", "#D8EFD9", "#2F7D3E", "#6FBF7A"),
        ("chem", "#D9E7DC", "#2F5D3A", "#7FA88A"),
        ("math", "#D6E2FA", "#274FA8", "#6E97EC"),
        ("hist", "#FBE8C4", "#8F5D0E", "#E8B85C"),
        ("econ", "#E5DEF8", "#5B41B0", "#9A86DE"),
        ("phil", "#FADAD6", "#B3372B", "#EC8A80"),
        ("teal", "#D3EEEC", "#1F6F6A", "#5DBDB5"),
        ("orange", "#FDE3D2", "#A4501A", "#F0A26E"),
        ("pink", "#F8DCEB", "#A33A74", "#E58BBE"),
        ("sky", "#D5ECF7", "#1E6A8F", "#6BB8DE"),
        ("olive", "#E8EDD2", "#5B6B1E", "#A9BA5E"),
        ("slate", "#E1E5EC", "#3F4C63", "#8D9AB0"),
        ("indigo", "#DEE0FA", "#3A3FA8", "#8489E6"),
        ("rose", "#FADCE1", "#A8304A", "#E8899B"),
        ("lime", "#E6F4CF", "#4A7012", "#9CCB52"),
        ("cyan", "#D2F0F5", "#16687A", "#5CC2D6"),
        ("brown", "#EEE2D6", "#6E4A2B", "#B78E68"),
        ("gold", "#F7EDC2", "#7A6410", "#D8BE4A"),
    ]

    static let entries: [String: (background: String, foreground: String, dot: String)] =
        Dictionary(uniqueKeysWithValues: ordered.map { ($0.key, ($0.background, $0.foreground, $0.dot)) })

    /// The built-in palette keys, sorted.
    public static var keys: [String] { entries.keys.sorted() }

    /// The built-in palette keys in picker order (mockup colours first).
    public static var orderedKeys: [String] { ordered.map(\.key) }

    /// Whether a course icon is one emoji (with any skin tone, flag or ZWJ sequence) rather than
    /// an icon name; plain digits and symbols are not emoji here.
    public static func isEmoji(_ text: String) -> Bool {
        guard text.count == 1, let first = text.unicodeScalars.first else { return false }
        return text.unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || (first.properties.isEmoji && text.unicodeScalars.contains { $0 == "\u{FE0F}" })
    }

    /// Style for an icon name and palette key.
    public static func style(icon: String, color: String) -> CourseStyle {
        let c = entries[color] ?? ("#E6E6E6", "#555555", "#9A9A9A")
        return CourseStyle(icon: icon.isEmpty ? "school" : icon, color: color.isEmpty ? "neutral" : color,
                           background: c.background, foreground: c.foreground, dot: c.dot)
    }
}
