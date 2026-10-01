import Foundation

/// Where a link's `#Heading` or `#^block` points in a note's text (Obsidian's rules: headings match
/// without their `#` marks and case, a block id is the `^id` at the end of a line).
enum LinkAnchor {
    static func line(of anchor: String, in text: String) -> Int? {
        let lines = text.components(separatedBy: "\n")
        if anchor.hasPrefix("^") {
            let id = anchor.lowercased()
            return lines.firstIndex { line in
                let words = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
                return words.last.map { $0.lowercased() == id } ?? false
            }
        }
        // `Note#Part#Section` names nested headings; the last one is the target.
        let wanted = normalized(anchor.split(separator: "#").last.map(String.init) ?? anchor)
        return lines.firstIndex { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("#") else { return false }
            let title = t.drop { $0 == "#" }
            guard title.first == " " else { return false }
            return normalized(String(title)) == wanted
        }
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
