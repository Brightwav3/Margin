import Foundation

extension AppEnvironment {
    /// Services over a new, empty vault in a temporary folder, for UI integration tests and
    /// previews that need real files. Remove it with `removeScratchVault(at:)` after `shutdown()`.
    public static func scratchVault(clock: any Clock = SystemClock(),
                                    watchInterval: TimeInterval = 0.05) async throws -> (env: AppEnvironment, url: URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("margin-scratch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let env = try await vault(at: url, clock: clock, watchInterval: watchInterval)
        return (env, url)
    }

    /// Deletes a folder made by `scratchVault`; any other path is left alone.
    public static func removeScratchVault(at url: URL) {
        guard url.lastPathComponent.hasPrefix("margin-scratch-"),
              url.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
