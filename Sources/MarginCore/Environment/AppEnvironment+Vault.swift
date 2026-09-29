import Foundation

extension AppEnvironment {
    /// Seconds between scans of the portable file watcher. The watcher reports a change one scan
    /// after it saw it (debounce), so an outside edit reaches the services after at most about
    /// twice this plus the scan time; 0.2 s keeps that clear of the 1 s the task views promise.
    public static let defaultWatchInterval: TimeInterval = 0.2

    /// Services over the vault folder at `url` (spec 05). Opens the vault, builds the index and
    /// starts watching for changes made by other programs. Throws `MarginError.notFound` when the
    /// folder does not exist and `.io` when it cannot be read.
    ///
    /// - Parameter watchInterval: seconds between file scans (the portable watcher; macOS uses the
    ///   same until the FSEvents backend lands). Defaults to `defaultWatchInterval`.
    public static func vault(at url: URL, clock: any Clock = SystemClock(),
                             watchInterval: TimeInterval = AppEnvironment.defaultWatchInterval) async throws -> AppEnvironment {
        let backend = try await VaultBackend.open(at: url, clock: clock, watchInterval: watchInterval)
        return AppEnvironment(
            clock: clock,
            courses: VaultCourseCatalog(backend: backend),
            notes: VaultNoteRepository(backend: backend),
            tasks: VaultTaskService(backend: backend),
            properties: VaultPropertyService(backend: backend),
            analysis: VaultNoteAnalysis(backend: backend),
            graph: VaultGraphService(backend: backend),
            shutdown: { await backend.shutdown() })
    }
}
