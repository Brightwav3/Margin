#if os(macOS)
import CoreGraphics
import CoreText
import Foundation

/// Lays exported Markdown out on A4 pages with Core Text (no AppKit in `MarginCore`).
struct PDFLayout {
    var page = CGSize(width: 595.28, height: 841.89)
    var margin: CGFloat = 56

    func render(markdown: String, title: String) throws -> Data {
        let text = attributed(markdown, title: title)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw MarginError.io("Could not start the PDF") }
        var box = CGRect(origin: .zero, size: page)
        let info = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Margin"] as CFDictionary
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, info) else { throw MarginError.io("Could not start the PDF") }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let frameRect = CGRect(x: margin, y: margin + 18, width: page.width - 2 * margin, height: page.height - 2 * margin - 18)
        var start = 0
        var number = 1
        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            drawFooter("\(number)", in: ctx)
            ctx.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            // A frame that fits nothing (an overlong unbreakable line) would loop forever.
            guard visible.length > 0 else { break }
            start += visible.length
            number += 1
        } while start < text.length
        ctx.closePDF()
        return data as Data
    }

    private func drawFooter(_ text: String, in ctx: CGContext) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs(font(9), color: Self.grey)))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: (page.width - width) / 2, y: margin / 2)
        CTLineDraw(line, ctx)
    }

    // MARK: Markdown → attributed text

    static let ink = CGColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1)
    static let grey = CGColor(red: 0.42, green: 0.44, blue: 0.49, alpha: 1)
    static let codeFill = CGColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    static let mark = CGColor(red: 1, green: 0.93, blue: 0.6, alpha: 1)

    func attributed(_ markdown: String, title: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // The note's own `# Title` would repeat the title printed on top.
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].trimmingCharacters(in: .whitespaces) == "# \(title)" {
            lines.remove(at: first)
        }
        out.append(NSAttributedString(string: title + "\n", attributes: attrs(font(22, bold: true), spacingAfter: 14)))
        var inCode = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t == "$$" || t == "%%" { inCode.toggle(); continue }
            if inCode {
                out.append(NSAttributedString(string: line + "\n", attributes: attrs(mono(9.5), background: Self.codeFill, indent: 8)))
                continue
            }
            if t.isEmpty { out.append(NSAttributedString(string: "\n", attributes: attrs(font(5)))); continue }
            if t == "---" || t == "***" { out.append(NSAttributedString(string: "\n", attributes: attrs(font(6)))); continue }
            let leading = line.prefix { $0 == "\t" || $0 == " " }
            let columns: Int = leading.reduce(0) { sum, c in sum + (c == "\t" ? 4 : 1) }
            let indentLevel = CGFloat(columns / 2)
            if let (level, body) = heading(t) {
                let size: CGFloat = [17, 14.5, 12.5, 11.5, 11, 11][min(level, 6) - 1]
                out.append(inline(body, base: font(size, bold: true), spacingBefore: level == 1 ? 12 : 8, spacingAfter: 4))
            } else if let (box, body) = task(t) {
                out.append(inline((box ? "☑ " : "☐ ") + body, base: font(11), indent: 14 + indentLevel * 7, hanging: 14))
            } else if let body = bullet(t) {
                out.append(inline("•  " + body, base: font(11), indent: 14 + indentLevel * 7, hanging: 12))
            } else if let (n, body) = numbered(t) {
                out.append(inline("\(n).  " + body, base: font(11), indent: 14 + indentLevel * 7, hanging: 16))
            } else if t.hasPrefix(">") {
                var body = t.drop { $0 == ">" || $0 == " " }
                if body.hasPrefix("[!"), let close = body.firstIndex(of: "]") {
                    let kind = body[body.index(body.startIndex, offsetBy: 2)..<close].capitalized
                    let rest = body[body.index(after: close)...].trimmingCharacters(in: CharacterSet(charactersIn: "-+ "))
                    body = Substring(rest.isEmpty ? kind : rest)
                    out.append(inline(String(body), base: font(11, bold: true), indent: 14, color: Self.grey))
                } else {
                    out.append(inline(String(body), base: font(11, italic: true), indent: 14, color: Self.grey))
                }
            } else {
                out.append(inline(t, base: font(11)))
            }
        }
        return out
    }

    private func heading(_ t: String) -> (Int, String)? {
        let level = t.prefix { $0 == "#" }.count
        guard (1...6).contains(level), t.dropFirst(level).first == " " else { return nil }
        return (level, String(t.dropFirst(level + 1)))
    }

    private func task(_ t: String) -> (Bool, String)? {
        for marker in ["- [ ] ", "* [ ] ", "- [x] ", "* [x] ", "- [X] ", "* [X] "] where t.hasPrefix(marker) {
            return (marker.contains("x") || marker.contains("X"), String(t.dropFirst(marker.count)))
        }
        return nil
    }

    private func bullet(_ t: String) -> String? {
        for marker in ["- ", "* ", "+ "] where t.hasPrefix(marker) { return String(t.dropFirst(2)) }
        return nil
    }

    private func numbered(_ t: String) -> (Int, String)? {
        let digits = t.prefix { $0.isNumber }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        let rest = t.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (n, String(rest.dropFirst(2)))
    }

    /// One paragraph with `**bold**`, `*italic*`, `` `code` ``, `==highlight==` and `~~strike~~`.
    private func inline(_ text: String, base: CTFont, indent: CGFloat = 0, hanging: CGFloat = 0, color: CGColor = PDFLayout.ink,
                        spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 3) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let size = CTFontGetSize(base)
        let baseBold = CTFontGetSymbolicTraits(base).contains(.traitBold)
        var bold = false, italic = false, code = false, highlight = false, strike = false
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            let f = code ? mono(size - 1) : font(size, bold: bold || baseBold, italic: italic || CTFontGetSymbolicTraits(base).contains(.traitItalic))
            // Core Text draws no strikethrough: struck text is grey instead.
            let a = attrs(f, color: strike ? Self.grey : color, background: code ? Self.codeFill : highlight ? Self.mark : nil)
            out.append(NSAttributedString(string: buffer, attributes: a))
            buffer = ""
        }
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i], next = i + 1 < chars.count ? chars[i + 1] : nil
            if c == "\\", let next, "*_`=~[]#".contains(next) { buffer.append(next); i += 2; continue }
            if c == "`" { flush(); code.toggle(); i += 1; continue }
            if !code {
                if c == "*", next == "*" { flush(); bold.toggle(); i += 2; continue }
                if c == "=", next == "=" { flush(); highlight.toggle(); i += 2; continue }
                if c == "~", next == "~" { flush(); strike.toggle(); i += 2; continue }
                if c == "*" || (c == "_" && (i == 0 || chars[i - 1] == " ")) { flush(); italic.toggle(); i += 1; continue }
            }
            buffer.append(c)
            i += 1
        }
        buffer.append("\n")
        flush()
        let p = paragraph(indent: indent, hanging: hanging, before: spacingBefore, after: spacingAfter)
        out.addAttribute(NSAttributedString.Key(kCTParagraphStyleAttributeName as String), value: p,
                         range: NSRange(location: 0, length: out.length))
        return out
    }

    private func attrs(_ font: CTFont, color: CGColor = PDFLayout.ink, background: CGColor? = nil, indent: CGFloat = 0,
                       spacingAfter: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph(indent: indent, hanging: 0, before: 0, after: spacingAfter),
        ]
        if let background { a[NSAttributedString.Key(kCTBackgroundColorAttributeName as String)] = background }
        return a
    }

    private func paragraph(indent: CGFloat, hanging: CGFloat, before: CGFloat, after: CGFloat) -> CTParagraphStyle {
        var first = indent, head = indent + hanging, spaceBefore = before, spaceAfter = after, multiple: CGFloat = 1.25
        return withUnsafeBytes(of: &first) { firstPtr in
            withUnsafeBytes(of: &head) { headPtr in
                withUnsafeBytes(of: &spaceBefore) { beforePtr in
                    withUnsafeBytes(of: &spaceAfter) { afterPtr in
                        withUnsafeBytes(of: &multiple) { multiplePtr in
                            let settings = [
                                CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: MemoryLayout<CGFloat>.size, value: firstPtr.baseAddress!),
                                CTParagraphStyleSetting(spec: .headIndent, valueSize: MemoryLayout<CGFloat>.size, value: headPtr.baseAddress!),
                                CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: MemoryLayout<CGFloat>.size, value: beforePtr.baseAddress!),
                                CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: afterPtr.baseAddress!),
                                CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: multiplePtr.baseAddress!),
                            ]
                            return CTParagraphStyleCreate(settings, settings.count)
                        }
                    }
                }
            }
        }
    }

    /// Inter when the app bundles it, else the system font.
    private func font(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> CTFont {
        let name = bold ? "Inter-SemiBold" : "Inter-Regular"
        var f = CTFontCreateWithName(name as CFString, size, nil)
        if (CTFontCopyPostScriptName(f) as String) != name {
            f = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil) ?? f
        }
        if italic, let slanted = CTFontCreateCopyWithSymbolicTraits(f, size, nil, .traitItalic, .traitItalic) { f = slanted }
        return f
    }

    private func mono(_ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil) ?? CTFontCreateWithName("Menlo" as CFString, size, nil)
    }
}
#endif
