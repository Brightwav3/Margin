import AppKit
import WebKit

/// Renders math (`$$ … $$`, KaTeX) and Mermaid diagrams of a note into images, offline: a hidden
/// web view loads the bundled `Resources/Render/render.html` (D-027) and the editor draws the
/// pictures outside the block being edited, like image embeds. Sources are passed as data
/// (`callAsyncJavaScript` arguments), the page allows no network and Mermaid runs in strict mode.
@MainActor
final class BlockRenderer: NSObject, WKNavigationDelegate {
    static let shared = BlockRenderer()

    enum Kind: String, Sendable { case math, mermaid }

    struct Rendered {
        var image: NSImage
        var isError: Bool
    }

    /// Called after a picture finished rendering, so the editor restyles.
    var onRendered: (() -> Void)?

    private var cache: [String: Rendered] = [:]
    private var queue: [(key: String, kind: Kind, source: String)] = []
    private var queued: Set<String> = []
    private var web: WKWebView?
    private var window: NSWindow?
    private var isReady = false
    private var isDraining = false

    /// Whether a picture has no visible pixel (sampled on a grid).
    static func isBlank(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return true }
        let rep = NSBitmapImageRep(cgImage: cg)
        let stepX = max(1, rep.pixelsWide / 40), stepY = max(1, rep.pixelsHigh / 20)
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.05,
                   c.redComponent + c.greenComponent + c.blueComponent < 2.7 { return false }
            }
        }
        return true
    }

    /// Mermaid is fetched by `scripts/fetch-render-libs.sh` (over the repository's file size limit).
    nonisolated static var hasMermaid: Bool {
        Bundle.module.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Render/mermaid") != nil
    }

    static func key(_ kind: Kind, _ source: String) -> String { kind.rawValue + "\u{1}" + source }

    /// The picture of a block, or `nil` while it is rendering (`onRendered` follows).
    func rendered(_ kind: Kind, _ source: String) -> Rendered? {
        let key = Self.key(kind, source)
        if let hit = cache[key] { return hit }
        if !queued.contains(key) {
            queued.insert(key)
            queue.append((key, kind, source))
            start()
        }
        return nil
    }

    func cached(key: String) -> Rendered? { cache[key] }

    /// Renders one block and waits for it (tests, export).
    func render(_ kind: Kind, _ source: String) async -> Rendered? {
        if let hit = rendered(kind, source) { return hit }
        let key = Self.key(kind, source)
        for _ in 0..<600 {
            try? await Task.sleep(for: .milliseconds(50))
            if let hit = cache[key] { return hit }
        }
        return nil
    }

    // MARK: Web view

    private func start() {
        if isReady { drain(); return }
        guard web == nil, let page = Bundle.module.url(forResource: "render", withExtension: "html", subdirectory: "Render") else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 760, height: 2400), configuration: config)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        // Off screen, but in a window: snapshots need a hosted view.
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        self.window = window
        web = view
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        drain()
    }

    /// Only the bundled page may load; links and redirects inside a diagram go nowhere.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.isFileURL == true && navigationAction.navigationType == .other ? .allow : .cancel
    }

    private func drain() {
        guard isReady, !isDraining, let web else { return }
        isDraining = true
        Task { @MainActor in
            defer { self.isDraining = false }
            while !self.queue.isEmpty {
                let job = self.queue.removeFirst()
                let result = try? await web.callAsyncJavaScript("return await render(kind, source)",
                                                                arguments: ["kind": job.kind.rawValue, "source": job.source],
                                                                contentWorld: .page) as? [String: Any]
                let width = (result?["width"] as? NSNumber)?.doubleValue ?? 0
                let height = (result?["height"] as? NSNumber)?.doubleValue ?? 0
                let isError = (result?["error"] as? Bool) ?? true
                var image: NSImage?
                if width > 0, height > 0 {
                    let snapshot = WKSnapshotConfiguration()
                    snapshot.rect = CGRect(x: 0, y: 0, width: width, height: height)
                    snapshot.afterScreenUpdates = true
                    // The first paint of the hidden page can come after the snapshot: take it again
                    // until it shows something.
                    for attempt in 0..<10 {
                        image = try? await web.takeSnapshot(configuration: snapshot)
                        if let image, !Self.isBlank(image) { break }
                        if attempt < 9 { try? await Task.sleep(for: .milliseconds(100)) }
                    }
                }
                self.cache[job.key] = Rendered(image: image ?? NSImage(size: NSSize(width: 1, height: 1)), isError: isError || image == nil)
                self.queued.remove(job.key)
                self.onRendered?()
            }
        }
    }
}
