import Foundation

extension AppEnvironment {
    /// Services over the vault folder at `url` (spec 05). Opens the vault, builds the index and
    /// starts watching for changes made by other programs. Throws `MarginError.notFound` when the
    /// folder does not exist and `.io` when it cannot be read.
    ///
    /// - Parameter watchInterval: seconds between file scans (the portable watcher; macOS uses the
    ///   same until the FSEvents backend lands).
    public static func vault(at url: URL, clock: any Clock = SystemClock(),
                             watchInterval: TimeInterval = 0.3) async throws -> AppEnvironment {
        let backend = try await VaultBackend.open(at: url, clock: clock, watchInterval: watchInterval)
        return AppEnvironment(
            clock: clock,
            courses: VaultCourseCatalog(backend: backend),
            notes: VaultNoteRepository(backend: backend),
            tasks: VaultTaskService(backend: backend),
            shutdown: { await backend.shutdown() })
    }
}
