import Foundation
import Testing
@testable import MarginCore

/// A vault on disk with the sample courses (`Fixtures.week5`) or only its semester, opened like the
/// app does. Keeps the folder alive as long as the value is.
struct CourseVault {
    let dir: TempDir
    let backend: VaultBackend
    let writer: VaultCourseCatalogWriter
    let catalog: VaultCourseCatalog
    let notes: VaultNoteRepository
    let tasks: VaultTaskService
    let clock: FixedClock

    static func open(sample: Bool = true) async throws -> CourseVault {
        let dir = TempDir()
        let clock = FixedClock()
        let store = try await VaultStore.open(root: dir.url, clock: clock, trash: PortableTrash())
        if sample {
            try await SampleVaultGenerator.generate(into: store, from: Fixtures.week5)
        } else {
            try await store.create(VaultPath(".margin/semesters.json"), content: SampleVaultGenerator.semestersJSON(Fixtures.week5.semester))
        }
        return try await reopen(dir, clock: clock)
    }

    /// A fresh backend over the same folder (what a restart of the app does).
    static func reopen(_ dir: TempDir, clock: FixedClock = FixedClock()) async throws -> CourseVault {
        let backend = try await VaultBackend.open(at: dir.url, clock: clock, watchInterval: 0.05, trash: PortableTrash())
        return CourseVault(dir: dir, backend: backend, writer: VaultCourseCatalogWriter(backend: backend),
                           catalog: VaultCourseCatalog(backend: backend), notes: VaultNoteRepository(backend: backend),
                           tasks: VaultTaskService(backend: backend), clock: clock)
    }

    func text(_ relative: String) -> String { dir.bytes(relative).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    func shutdown() async { await backend.shutdown() }
}

/// The code of the `MarginError` a call throws, `nil` when it does not throw.
func errorCode<T>(_ body: () async throws -> T) async -> String? {
    do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other" }
}
