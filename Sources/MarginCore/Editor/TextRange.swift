/// A range of UTF-16 code units (`location`, `length`) into an editor document.
///
/// The Mac editor is an `NSTextView`, whose `NSRange` counts UTF-16 code units, so every offset in
/// the editor layer (tokens, blocks, edits, cursor positions) is a UTF-16 offset. Unlike
/// `ByteRange` (UTF-8, used by the vault scanner) these ranges can be handed to `NSRange` as is.
/// Ranges are half-open: `location ..< location + length`.
public struct TextRange: Sendable, Hashable, Codable {
    public var location: Int
    public var length: Int

    /// Negative values are clamped to zero.
    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    public init(_ range: Range<Int>) {
        self.init(location: range.lowerBound, length: range.upperBound - range.lowerBound)
    }

    public var end: Int { location + length }
    public var isEmpty: Bool { length == 0 }
    public var range: Range<Int> { location..<end }

    /// `true` when both ranges share at least one code unit, or when an empty range sits inside
    /// (or at the edges of) the other range.
    public func intersects(_ other: TextRange) -> Bool {
        if isEmpty || other.isEmpty {
            let p = isEmpty ? location : other.location
            let r = isEmpty ? other : self
            return p >= r.location && p <= r.end
        }
        return location < other.end && other.location < end
    }

    public func contains(offset: Int) -> Bool { offset >= location && offset < end }
}
