import Testing
@testable import MarginCore

/// Renders tokens as `name|text` (text with newlines shown as `⏎`), for readable expectations.
func render(_ text: String, _ tokens: [MarkdownToken]) -> [String] {
    let u = Array(text.utf16)
    return tokens.map { t in
        let slice = String(decoding: u[t.range.location..<t.range.end], as: UTF16.self)
            .map { $0 == "\n" ? "⏎" : String($0) }.joined()
        return "\(t.kind.name)|\(slice)"
    }
}

func render(_ text: String) -> [String] { render(text, MarkdownTokenizer.tokenize(text)) }
