/// What a block is.
public enum BlockKind: Sendable, Hashable, Codable {
    case paragraph
    case heading(level: Int)
    /// One list item including its indented continuation lines.
    case listItem(ordered: Bool)
    case task(checked: Bool)
    /// Fenced code from the opening to the closing fence. `terminated` is `false` for a fence that
    /// runs to the end of the document.
    case codeFence(info: String?, terminated: Bool)
    case indentedCode
    case table
    /// Consecutive `>` lines that do not open a callout.
    case quote
    /// A blockquote opened by `> [!type]` (type lowercased); it runs over the following `>` lines.
    case callout(type: String)
    case frontmatter
    case horizontalRule
    /// One or more blank lines.
    case blank
}

/// One block of the document.
public struct Block: Sendable, Hashable {
    public var kind: BlockKind
    /// UTF-16 range from the start of the first line to the end of the last line's content. The
    /// terminator of the last line is not included.
    public var range: TextRange
    /// Lines covered by the block (0-based, half-open).
    public var lineRange: Range<Int>
}

/// The document split into blocks that tile all its lines, for live preview: the block holding the
/// cursor is shown as raw markdown, all others rendered.
///
/// Built from the tokenizer's line classification (`MarkdownTokenizer.blockModel()`), so blocks and
/// tokens always agree. Rules:
/// - Every line belongs to exactly one block; the model always has at least one block (an empty
///   document is a single `.blank` block).
/// - A paragraph is a run of non-blank lines that are not another block. A heading, a horizontal
///   rule and every list item is a block of its own; indented lines directly under a list item
///   belong to it.
/// - Code fences, frontmatter and tables run over all their lines (including blank lines inside a
///   fence). Indented code includes blank lines between its indented lines.
/// - Consecutive `>` lines form one quote; a `> [!type]` line starts a new callout.
public struct BlockModel: Sendable, Hashable {
    public let blocks: [Block]

    /// Builds the model for `text`.
    public init(text: String) {
        self = MarkdownTokenizer(text: text).blockModel()
    }

    init(lineStarts: [Int], lineEnds: [Int], kinds: [LineKind]) {
        var blocks: [Block] = []

        func extend(_ k: Int) {
            blocks[blocks.count - 1].lineRange = blocks[blocks.count - 1].lineRange.lowerBound..<(k + 1)
            blocks[blocks.count - 1].range.length = lineEnds[k] - blocks[blocks.count - 1].range.location
        }
        func start(_ kind: BlockKind, _ k: Int) {
            blocks.append(Block(
                kind: kind,
                range: TextRange(location: lineStarts[k], length: lineEnds[k] - lineStarts[k]),
                lineRange: k..<(k + 1)))
        }

        for k in 0..<kinds.count {
            let last = blocks.last?.kind
            switch kinds[k] {
            case .blank:
                if case .blank? = last { extend(k) } else { start(.blank, k) }
            case .frontmatter:
                if case .frontmatter? = last { extend(k) } else { start(.frontmatter, k) }
            case .fenceOpen(let info):
                start(.codeFence(info: info, terminated: false), k)
            case .fenceBody:
                if case .codeFence? = last { extend(k) } else { start(.codeFence(info: nil, terminated: false), k) }
            case .fenceClose:
                if case .codeFence(let info, _)? = last {
                    extend(k)
                    blocks[blocks.count - 1].kind = .codeFence(info: info, terminated: true)
                } else {
                    start(.codeFence(info: nil, terminated: true), k)
                }
            case .indentedCode:
                if case .indentedCode? = last {
                    extend(k)
                } else if case .blank? = last, blocks.count >= 2, case .indentedCode = blocks[blocks.count - 2].kind {
                    blocks.removeLast()
                    extend(k)
                } else {
                    start(.indentedCode, k)
                }
            case .heading(let level):
                start(.heading(level: level), k)
            case .listItem(let ordered, let task):
                if let checked = task { start(.task(checked: checked), k) } else { start(.listItem(ordered: ordered), k) }
            case .listContinuation:
                switch last {
                case .listItem?, .task?, .paragraph?: extend(k)
                default: start(.paragraph, k)
                }
            case .quote(let callout):
                if let type = callout {
                    start(.callout(type: type), k)
                } else {
                    switch last {
                    case .quote?, .callout?: extend(k)
                    default: start(.quote, k)
                    }
                }
            case .table:
                if case .table? = last { extend(k) } else { start(.table, k) }
            case .horizontalRule:
                start(.horizontalRule, k)
            case .paragraph:
                if case .paragraph? = last { extend(k) } else { start(.paragraph, k) }
            }
        }
        self.blocks = blocks
    }

    /// Index into `blocks` of the block holding `cursorOffset` (a UTF-16 offset, clamped to the
    /// document). A cursor at the end of a line belongs to that line's block; one right after a
    /// line break belongs to the next line's block.
    public func activeBlockIndex(at cursorOffset: Int) -> Int {
        var lo = 0, hi = blocks.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if blocks[mid].range.location <= cursorOffset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// The block the cursor is in.
    public func activeBlock(at cursorOffset: Int) -> Block {
        blocks[activeBlockIndex(at: cursorOffset)]
    }

    /// Blocks intersecting `range` (an empty range selects the block at its location).
    public func blocks(intersecting range: TextRange) -> [Block] {
        let first = activeBlockIndex(at: range.location)
        let last = activeBlockIndex(at: range.isEmpty ? range.location : range.end - 1)
        return Array(blocks[first...max(first, last)])
    }
}
