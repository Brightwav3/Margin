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
    /// - Parameter progress: called while the index is built (0 … 100 %, the last element complete),
    ///   for a loading screen. `AppEnvironment.indexStatus` gives the same to a late subscriber.
    /// - Parameter reminderCenter: where class reminders are shown; the macOS app passes
    ///   `UserNotificationCenter`, the default keeps them in memory.
    public static func vault(at url: URL, clock: any Clock = SystemClock(),
                             watchInterval: TimeInterval = AppEnvironment.defaultWatchInterval,
                             reminderCenter: any ReminderCenter = InMemoryReminderCenter(),
                             progress: (@Sendable (IndexProgress) -> Void)? = nil) async throws -> AppEnvironment {
        try await vault(at: url, clock: clock, watchInterval: watchInterval, reminderCenter: reminderCenter,
                        progress: progress, fileSystem: POSIXFileSystem())
    }

    /// `vault(at:)` over a given file system (tests inject faults here).
    static func vault(at url: URL, clock: any Clock, watchInterval: TimeInterval,
                      reminderCenter: any ReminderCenter = InMemoryReminderCenter(),
                      progress: (@Sendable (IndexProgress) -> Void)? = nil,
                      fileSystem: any FileSystem) async throws -> AppEnvironment {
        let backend = try await VaultBackend.open(at: url, clock: clock, watchInterval: watchInterval,
                                                  fileSystem: fileSystem, onProgress: progress)
        let settings = VaultSettingsStore(store: backend.store)
        return AppEnvironment(
            clock: clock,
            courses: VaultCourseCatalog(backend: backend),
            notes: VaultNoteRepository(backend: backend),
            tasks: VaultTaskService(backend: backend),
            capture: VaultCaptureService(backend: backend),
            inbox: VaultInboxService(backend: backend),
            properties: VaultPropertyService(backend: backend),
            analysis: VaultNoteAnalysis(backend: backend),
            graph: VaultGraphService(backend: backend),
            courseWriter: VaultCourseCatalogWriter(backend: backend),
            settings: settings, semesters: VaultSemesterStore(backend: backend),
            indexStatus: VaultIndexStatus(backend: backend),
            grades: VaultGradeService(backend: backend),
            history: VaultHistoryService(backend: backend),
            reminders: CatalogReminderService(courses: VaultCourseCatalog(backend: backend), center: reminderCenter, clock: clock),
            syllabus: VaultSyllabusService(backend: backend),
            export: VaultExportService(backend: backend),
            search: VaultSearchService(backend: backend),
            shutdown: { settings.finish(); await backend.shutdown() })
    }
}
