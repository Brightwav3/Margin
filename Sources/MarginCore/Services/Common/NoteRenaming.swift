import Foundation

/// The text side of renaming a note, shared by the fixture and the vault.
enum NoteRenaming {
    static func requireTitle(_ title: String) throws -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw MarginError.invalid("A note needs a title") }
        return t
    }

    /// The body with its first `# old` heading turned into `# new` (other headings stay).
    static func retitle(body: String, from old: String, to new: String) -> String {
        var lines = body.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.hasPrefix("# ") {
            if line.dropFirst(2).trimmingCharacters(in: .whitespaces) == old { lines[i] = "# " + new }
            break
        }
        return lines.joined(separator: "\n")
    }

    /// `[[Old]]`, `[[Old|alias]]`, `[[Old#heading]]` and embeds pointing at `old` now point at `new`.
    static func rewriteLinks(in text: String, from old: String, to new: String) -> String {
        guard text.contains("[[") else { return text }
        let escaped = NSRegularExpression.escapedPattern(for: old)
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[" + escaped + "(?=[\\]|#^])", options: [.caseInsensitive]) else { return text }
        let template = NSRegularExpression.escapedTemplate(for: "[[" + new)
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
}
