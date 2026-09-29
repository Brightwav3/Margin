import AppKit
import MarginUI
import SwiftUI

// Renders one gallery screen to a PNG without launching the (sandboxed) app.
// Usage: margin-snap <screen-id> <out.png>   (wrapped by scripts/snap.sh)

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: margin-snap <screen-id> <out.png>\n".utf8))
    exit(2)
}

MainActor.assumeIsolated {
    guard let screen = MarginScreens.screen(id: args[1]) else {
        let ids = MarginScreens.all.map(\.id).joined(separator: ", ")
        FileHandle.standardError.write(Data("unknown screen \(args[1]); known: \(ids)\n".utf8))
        exit(1)
    }
    _ = NSApplication.shared
    let size = MarginScreens.size
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    let host = NSHostingView(rootView: screen.view().frame(width: size.width, height: size.height))
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    // Let SwiftUI settle (fonts, lazy grids) before capturing.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do {
        try png.write(to: URL(fileURLWithPath: args[2]))
    } catch {
        FileHandle.standardError.write(Data("cannot write \(args[2]): \(error)\n".utf8))
        exit(1)
    }
}
