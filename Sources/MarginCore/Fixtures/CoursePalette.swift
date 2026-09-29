/// Maps the `color:` key of a `_course.md` to the course's colours (vault spec 05 §5).
///
/// The vault stores only the palette key; the tints are domain data shared by the fixture and the
/// vault implementation so a course looks the same from either. Unknown keys get a neutral grey
/// (the file stays valid, the app never fails on a hand-edited key).
public enum CoursePalette {
    /// The built-in keys with their light tint, foreground and dot colours.
    static let entries: [String: (background: String, foreground: String, dot: String)] = [
        "bio": ("#D8EFD9", "#2F7D3E", "#6FBF7A"),
        "chem": ("#D9E7DC", "#2F5D3A", "#7FA88A"),
        "math": ("#D6E2FA", "#274FA8", "#6E97EC"),
        "hist": ("#FBE8C4", "#8F5D0E", "#E8B85C"),
        "econ": ("#E5DEF8", "#5B41B0", "#9A86DE"),
        "phil": ("#FADAD6", "#B3372B", "#EC8A80"),
    ]

    /// The built-in palette keys, sorted.
    public static var keys: [String] { entries.keys.sorted() }

    /// Style for an icon name and palette key.
    public static func style(icon: String, color: String) -> CourseStyle {
        let c = entries[color] ?? ("#E6E6E6", "#555555", "#9A9A9A")
        return CourseStyle(icon: icon.isEmpty ? "school" : icon, color: color.isEmpty ? "neutral" : color,
                           background: c.background, foreground: c.foreground, dot: c.dot)
    }
}
