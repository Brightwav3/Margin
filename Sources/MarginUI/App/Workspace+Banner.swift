import AppKit
import MarginCore
import UniformTypeIdentifiers

/// Course banners (M3-05): picked from disk, stored in the vault by `CourseCatalogWriter.setBanner`.
extension Workspace {
    func chooseBanner(for course: Course) {
        let panel = NSOpenPanel()
        panel.title = "Choose a banner for \(course.name)"
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { show("Could not read the picture", error: true); return }
        setBanner(data, for: course)
    }

    /// Stores (`data`) or removes (`nil`) the banner and refreshes the course cards.
    func setBanner(_ data: Data?, for course: Course) {
        perform(data == nil ? "Remove banner" : "Change banner") {
            _ = try await self.env.courseWriter.setBanner(data, course: course.id, actor: .user, baseVersion: nil,
                                                          dryRun: false, idempotencyKey: nil)
            await self.courses.reloadBanner(course.id)
            self.show(data == nil ? "Banner removed" : "Banner changed", icon: "image")
        }
    }
}
