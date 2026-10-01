import AppKit
import WebKit

// Renders an HTML file to a PNG with WebKit: webshot <html> <out.png> <width> <height>
// (the page grows to its scroll size, up to 6000 × 12000). Used by scripts/ref-mockups.sh.
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let size = NSSize(width: Double(args[3])!, height: Double(args[4])!)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

final class Shot: NSObject, WKNavigationDelegate {
    let web: WKWebView
    init(size: NSSize) {
        web = WKWebView(frame: NSRect(origin: .zero, size: size))
        super.init()
        web.navigationDelegate = self
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            webView.evaluateJavaScript("[document.documentElement.scrollWidth, document.documentElement.scrollHeight]") { r, _ in
                if let a = r as? [Double], a.count == 2 {
                    webView.frame.size = NSSize(width: max(size.width, min(a[0], 6000)), height: max(size.height, min(a[1], 12000)))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let cfg = WKSnapshotConfiguration()
                    webView.takeSnapshot(with: cfg) { image, error in
                        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                              let png = rep.representation(using: .png, properties: [:]) else { print("ERR", error as Any); exit(1) }
                        try? png.write(to: out); print("OK", webView.frame.size); exit(0)
                    }
                }
            }
        }
    }
}
let shot = Shot(size: size)
let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = shot.web
shot.web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("TIMEOUT"); exit(2) }
app.run()
