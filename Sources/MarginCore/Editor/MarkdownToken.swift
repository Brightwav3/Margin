/// What a token marks. Tokens describe syntax only; the text is read from the document.
///
/// Conventions:
/// - Multi-line constructs are reported line by line: frontmatter body lines (`.frontmatter`),
///   fenced code body lines (`.codeLine`) and indented code lines (`.indentedCodeLine`) each get
///   one token per non-empty line. Use `BlockModel` for whole-block ranges.
/// - Inline constructs (`.emphasis`, `.strong`, `.strikethrough`, `.inlineCode`, links) never span
///   lines. Their range includes the delimiters (`**`, `` ` ``, `[[`, ...). Marker widths are fixed:
///   2 for `.strong` and `.strikethrough`, 1 for `.emphasis`, the backtick run for `.inlineCode`.
/// - Tokens are ordered by `range.location` ascending; when two tokens start at the same offset the
///   enclosing one comes first. Nested tokens are always fully inside their parent (for example a
///   `.wikilinkTarget` inside a `.wikilink`), tokens never partially overlap.
public enum MarkdownTokenKind: Sendable, Hashable, Codable {
    /// The `---` (or closing `...`) line of the YAML frontmatter.
    case frontmatterDelimiter
    /// One line of frontmatter content between the delimiters.
    case frontmatter
    /// The `#` characters of an ATX heading (no trailing space).
    case headingMarker(level: Int)
    /// The trimmed heading text without the closing `#`s.
    case headingText(level: Int)
    /// `-`, `*` or `+` of a bullet list item.
    case listBullet
    /// `1.` or `1)` of an ordered list item (digits and the delimiter).
    case listOrdered
    /// The `[ ]` / `[x]` box of a task (three code units).
    case taskCheckbox(checked: Bool)
    /// One `>` of a blockquote (nested quotes yield several).
    case blockquoteMarker
    /// `[!note]` of a callout, brackets included. `type` is lowercased.
    case callout(type: String)
    /// The run of backticks or tildes of a code fence (opening and closing).
    case codeFenceMarker
    /// The info string after an opening fence (`swift` in ```` ```swift ````).
    case codeInfo
    /// One line of fenced code (the whole line, indentation included).
    case codeLine
    /// One line of indented code (the whole line).
    case indentedCodeLine
    /// `` `code` `` including the backticks.
    case inlineCode
    case emphasis
    case strong
    case strikethrough
    /// `[[...]]` or, with `embed`, `![[...]]` (range includes the `!`).
    case wikilink(embed: Bool)
    case wikilinkTarget
    /// The part after `#` (without it).
    case wikilinkHeading
    /// The part after `|` (without it).
    case wikilinkAlias
    /// `[text](dest)` or, with `embed`, `![alt](src)` (range includes the `!`).
    case link(embed: Bool)
    /// The text between `[` and `]`.
    case linkText
    /// The destination inside `( )` (without angle brackets or title).
    case linkDestination
    /// `#tag` including the `#`.
    case tag
    /// `@…` due token of a task, including `@` (and spaces before the word, as in `@ Tue`).
    case due
    /// `^t-4f2a` block id at the end of a line, including the caret.
    case blockID
    /// A whole table line (trimmed). `header` marks the first row.
    case tableRow(header: Bool)
    /// The `|---|---|` line under the header row.
    case tableDelimiterRow
    /// `---`, `***` or `___` on its own line.
    case horizontalRule
    /// `==text==` including the `=`s (Obsidian highlight).
    case highlight
    /// `%%text%%` on one line, including the `%`s (Obsidian comment).
    case comment
    /// The `%%` line opening or closing a block comment.
    case commentFence
    /// One line inside a block comment.
    case commentLine
    /// `$x$` inline math, including the dollars.
    case inlineMath
    /// The `$$` line opening or closing a math block.
    case mathFence
    /// One line of a math block.
    case mathLine
    /// `\*` and other escaped punctuation: the backslash and the character.
    case escape
    /// `[^1]` footnote reference (or the label of a `[^1]:` definition at the start of a line).
    case footnoteRef(definition: Bool)
    /// `^[text]` inline footnote, including the caret and brackets.
    case inlineFootnote

    /// Stable short name used in diagnostics and tests, for example `heading.marker(2)`.
    public var name: String {
        switch self {
        case .frontmatterDelimiter: "frontmatter.delimiter"
        case .frontmatter: "frontmatter"
        case .headingMarker(let l): "heading.marker(\(l))"
        case .headingText(let l): "heading.text(\(l))"
        case .listBullet: "list.bullet"
        case .listOrdered: "list.ordered"
        case .taskCheckbox(let c): "task.checkbox(\(c ? "x" : " "))"
        case .blockquoteMarker: "quote.marker"
        case .callout(let t): "callout(\(t))"
        case .codeFenceMarker: "code.fence"
        case .codeInfo: "code.info"
        case .codeLine: "code.line"
        case .indentedCodeLine: "code.indented"
        case .inlineCode: "code.inline"
        case .emphasis: "emphasis"
        case .strong: "strong"
        case .strikethrough: "strike"
        case .wikilink(let e): e ? "embed.wikilink" : "wikilink"
        case .wikilinkTarget: "wikilink.target"
        case .wikilinkHeading: "wikilink.heading"
        case .wikilinkAlias: "wikilink.alias"
        case .link(let e): e ? "embed.link" : "link"
        case .linkText: "link.text"
        case .linkDestination: "link.destination"
        case .tag: "tag"
        case .due: "due"
        case .blockID: "block.id"
        case .tableRow(let h): h ? "table.header" : "table.row"
        case .tableDelimiterRow: "table.delimiter"
        case .horizontalRule: "hr"
        case .highlight: "highlight"
        case .comment: "comment"
        case .commentFence: "comment.fence"
        case .commentLine: "comment.line"
        case .inlineMath: "math.inline"
        case .mathFence: "math.fence"
        case .mathLine: "math.line"
        case .escape: "escape"
        case .footnoteRef(let d): d ? "footnote.definition" : "footnote.ref"
        case .inlineFootnote: "footnote.inline"
        }
    }
}

/// A syntax token: what it is and where it is (UTF-16 offsets, see `TextRange`).
public struct MarkdownToken: Sendable, Hashable, Codable {
    public var kind: MarkdownTokenKind
    public var range: TextRange

    public init(kind: MarkdownTokenKind, range: TextRange) {
        self.kind = kind
        self.range = range
    }
}
