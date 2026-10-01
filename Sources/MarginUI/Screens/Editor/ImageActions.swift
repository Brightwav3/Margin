import AppKit
import UniformTypeIdentifiers
import Vision

/// A picture in a note line: `![[name.png|300]]` or `![alt|300](name.png)`.
struct ImageEmbed: Equatable {
    var name: String
    var width: String?
    /// The embed in the line (UTF-16 offsets).
    var range: NSRange
    var wiki: Bool

    static func parse(_ line: String) -> ImageEmbed? {
        let ns = line as NSString
        if let m = try? NSRegularExpression(pattern: #"!\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#)
            .firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let spec = m.range(at: 2).location == NSNotFound ? nil : ns.substring(with: m.range(at: 2))
            return ImageEmbed(name: ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces),
                              width: spec, range: m.range, wiki: true)
        }
        if let m = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#)
            .firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let alt = ns.substring(with: m.range(at: 1))
            let dest = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
            let width = alt.split(separator: "|").dropFirst().last.map(String.init)
            return ImageEmbed(name: dest.removingPercentEncoding ?? dest, width: width, range: m.range, wiki: false)
        }
        return nil
    }

    /// The same embed at another width (`nil` = original size).
    func resized(_ width: Int?, in line: String) -> String {
        let ns = line as NSString
        let source = ns.substring(with: range)
        let replacement: String
        if wiki {
            replacement = "![[\(name)" + (width.map { "|\($0)" } ?? "") + "]]"
        } else {
            let altEnd = (source as NSString).range(of: "](")
            let alt = (source as NSString).substring(with: NSRange(location: 2, length: altEnd.location - 2))
            let base = alt.split(separator: "|").first.map(String.init) ?? ""
            let dest = (source as NSString).substring(from: NSMaxRange(altEnd))
            replacement = "![" + base + (width.map { "|\($0)" } ?? "") + "](" + dest
        }
        return ns.replacingCharacters(in: range, with: replacement)
    }
}

/// The image menu (1h): open, copy, save, size, caption and text extraction.
@MainActor
enum ImageActions {
    static func data(_ name: String) async -> Data? { await EmbedImages.shared.loader?(name) }

    static func openFullSize(_ name: String) {
        guard let image = EmbedImages.shared.image(name) else { return }
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        var size = image.size
        let fit = min(1, (screen.width * 0.8) / size.width, (screen.height * 0.8) / size.height)
        size = NSSize(width: size.width * fit, height: size.height * fit)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = name
        window.isReleasedWhenClosed = false
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        Self.windows.append(window)
    }
    private static var windows: [NSWindow] = []

    static func copy(_ name: String) {
        guard let image = EmbedImages.shared.image(name) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    static func saveAs(_ name: String, workspace: Workspace) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (name as NSString).lastPathComponent
        if let type = UTType(filenameExtension: (name as NSString).pathExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            guard let bytes = await data(name) else { workspace.show("Could not read the picture", error: true); return }
            do {
                try bytes.write(to: url, options: .atomic)
                workspace.show("Picture saved")
            } catch {
                workspace.show("Could not save the picture", error: true)
            }
        }
    }

    /// Recognized text of the picture (Czech and English), line by line.
    nonisolated static func recognizeText(in data: Data) async -> [String] {
        guard let image = NSImage(data: data), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        return await withCheckedContinuation { done in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }
                done.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["cs-CZ", "en-US"]
            request.usesLanguageCorrection = true
            do { try VNImageRequestHandler(cgImage: cg).perform([request]) } catch { done.resume(returning: []) }
        }
    }

    /// Puts the picture's text under it as a quote, so it is searchable.
    static func extractText(_ name: String, line: Int, handle: EditorHandle, workspace: Workspace) {
        Task { @MainActor in
            guard let bytes = await data(name) else { workspace.show("Could not read the picture", error: true); return }
            let lines = await recognizeText(in: bytes)
            guard !lines.isEmpty else { workspace.show("No text found in the picture", icon: "info"); return }
            insertBelow(line, "> " + lines.joined(separator: "\n> "), handle: handle)
            workspace.show("Text extracted (\(lines.count) lines)")
        }
    }

    static func resize(_ width: Int?, line: Int, handle: EditorHandle) {
        guard let tv = handle.textView, let range = EditorMenus.lineRange(line, in: tv.string as NSString) else { return }
        let text = (tv.string as NSString).substring(with: range)
        guard let embed = ImageEmbed.parse(text) else { return }
        tv.replace(range, with: embed.resized(width, in: text))
    }

    /// A caption is an italic line under the picture; the caret lands in it.
    static func addCaption(line: Int, handle: EditorHandle) {
        insertBelow(line, "*Popisek*", handle: handle)
        guard let tv = handle.textView, let range = EditorMenus.lineRange(line + 1, in: tv.string as NSString) else { return }
        tv.setSelectedRange(NSRange(location: range.location + 1, length: 7))
        tv.window?.makeFirstResponder(tv)
    }

    static func insertBelow(_ line: Int, _ text: String, handle: EditorHandle) {
        guard let tv = handle.textView, let range = EditorMenus.lineRange(line, in: tv.string as NSString) else { return }
        let ns = tv.string as NSString
        let endsWithNewline = range.length > 0 && ns.character(at: NSMaxRange(range) - 1) == 10
        let at = NSRange(location: NSMaxRange(range), length: 0)
        tv.replace(at, with: (endsWithNewline ? "" : "\n") + text + "\n")
    }
}
