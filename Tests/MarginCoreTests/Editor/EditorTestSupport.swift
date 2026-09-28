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

extension BlockKind {
    var name: String {
        switch self {
        case .paragraph: "paragraph"
        case .heading(let l): "heading(\(l))"
        case .listItem(let o): o ? "item(ordered)" : "item"
        case .task(let c): "task(\(c ? "x" : " "))"
        case .codeFence(let info, let t): "fence(\(info ?? "-"),\(t ? "closed" : "open"))"
        case .indentedCode: "indented"
        case .table: "table"
        case .quote: "quote"
        case .callout(let t): "callout(\(t))"
        case .frontmatter: "frontmatter"
        case .horizontalRule: "hr"
        case .blank: "blank"
        }
    }
}

/// Renders blocks as `kind L<first>-<last> text` (newlines as `⏎`).
func renderBlocks(_ text: String) -> [String] {
    let u = Array(text.utf16)
    return BlockModel(text: text).blocks.map { b in
        let slice = String(decoding: u[b.range.location..<b.range.end], as: UTF16.self)
            .map { $0 == "\n" ? "⏎" : String($0) }.joined()
        return "\(b.kind.name) L\(b.lineRange.lowerBound)-\(b.lineRange.upperBound - 1) \(slice)"
    }
}
