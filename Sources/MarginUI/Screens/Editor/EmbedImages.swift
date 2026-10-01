import AppKit
import MarginCore

/// Pictures of `![[name.png]]` embeds (Obsidian): loaded once through `NoteRepository.attachment`,
/// kept by name, drawn by the text view in the room the styler reserves.
@MainActor
final class EmbedImages {
    static let shared = EmbedImages()
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"]

    private var images: [String: NSImage] = [:]
    private var failed: Set<String> = []
    private var loading: Set<String> = []
    /// Reads an embedded file (set by the editor that is on screen).
    var loader: ((String) async -> Data?)?
    /// Called after an image arrived, so the editor restyles and makes room for it.
    var onLoaded: (() -> Void)?

    static func isImage(_ name: String) -> Bool {
        extensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// The image, or nil while it loads (the load starts here) or when it cannot be read.
    func image(_ name: String) -> NSImage? {
        if let hit = images[name] { return hit }
        guard !failed.contains(name), !loading.contains(name), let loader else { return nil }
        loading.insert(name)
        Task { @MainActor in
            let data = await loader(name)
            loading.remove(name)
            if let data, let image = NSImage(data: data) { images[name] = image; onLoaded?() } else { failed.insert(name) }
        }
        return nil
    }

    func didFail(_ name: String) -> Bool { failed.contains(name) }

    /// Width × height an image is shown at: its own size, at most `maxWidth` wide; `|200` or
    /// `|200x100` in the embed sets the width (and height).
    static func displaySize(of image: NSImage, spec: String?, maxWidth: CGFloat) -> NSSize {
        var size = image.size
        if size.width <= 0 || size.height <= 0 { size = NSSize(width: 320, height: 200) }
        let ratio = size.height / size.width
        if let spec {
            let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
            if let w = parts.first { size = NSSize(width: w, height: parts.count > 1 ? parts[1] : w * ratio) }
        }
        if size.width > maxWidth { size = NSSize(width: maxWidth, height: maxWidth * size.height / size.width) }
        return size
    }
}
