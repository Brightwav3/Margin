import AppKit
import SwiftUI

/// Lucide icons as template images for native menus (context menus, NSMenu): 16 pt, tinted by
/// the menu like SF Symbols. Rendered once per name.
@MainActor
enum MenuIcons {
    private static var cache: [String: NSImage] = [:]

    static func nsImage(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let renderer = ImageRenderer(content: Icon(name, size: 16, color: .black).frame(width: 16, height: 16))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        cache[name] = image
        return image
    }

    static func image(_ name: String) -> Image {
        nsImage(name).map { Image(nsImage: $0) } ?? Image(systemName: "circle")
    }
}

/// A menu row with a Lucide icon (mockup 4a): `MenuItem("Rename…", "edit") { … }`.
struct MenuItem: View {
    let title: String
    let icon: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, _ icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.role = role; self.action = action
    }

    var body: some View {
        Button(role: role, action: action) { Label { Text(title) } icon: { MenuIcons.image(icon) } }
    }
}
