import Foundation

/// Makes new semesters and new vaults (M11-02.B; spec 05 §1).
///
/// A new vault is the smallest one that opens without errors:
///
/// ```
/// <Vault>/
/// ├─ <Semester>/            the first semester, empty
/// ├─ _inbox/
/// ├─ _archive/
/// └─ .margin/
///    ├─ semesters.json      [ the first semester ]
///    └─ settings.json       {}
/// ```
///
/// `AppEnvironment.vault(at:)` opens it, every service answers with empty results (no courses, notes,
/// tasks, inbox items or graph nodes), and the semester is the current one.
public struct SemesterFactory: Sendable {
    let store: VaultStore

    init(store: VaultStore) { self.store = store }

    /// Creates the empty vault at `url` with its first semester and returns that semester.
    ///
    /// - Throws: `.conflict` when the folder exists and is not empty (an existing vault or a folder
    ///   of notes is opened, never initialized over), `.invalid` for a bad semester (see
    ///   `SemesterStore`), `.io` on disk errors. A failure halfway leaves the files made so far;
    ///   the folder is then no longer empty, so nothing is overwritten by a second attempt.
    @discardableResult
    public static func initializeVault(at url: URL, firstSemester new: NewSemester,
                                       clock: any Clock = SystemClock()) async throws -> Semester {
        let semester = try SemesterRules.make(new, among: [])
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) {
            guard isFolder.boolValue else { throw MarginError.invalid("\(url.lastPathComponent) is a file, not a folder") }
            let entries: [String]
            do { entries = try FileManager.default.contentsOfDirectory(atPath: url.path) }
            catch { throw MarginError.io("Cannot read \(url.lastPathComponent): \(error)") }
            guard entries.isEmpty else { throw MarginError.conflict("\(url.lastPathComponent) is not empty; open it as a vault instead") }
        }
        let store = try await VaultStore.open(root: url, clock: clock, createIfMissing: true)
        let factory = SemesterFactory(store: store)
        try await factory.createFolder(for: semester)
        for folder in ["_inbox", SemesterArchiver.folderName] { try await store.createFolder(VaultPath(folder)) }
        try await store.create(VaultPath(SemesterArchiver.semestersFile), content: SemesterRules.json([semester]))
        try await store.create(VaultPath(VaultSettingsStore.file), content: SettingsDocument().render())
        return semester
    }

    /// The folder of `semester` (`<name>/`), created when missing.
    @discardableResult
    func createFolder(for semester: Semester) async throws -> VaultPath {
        let path = try VaultPath(components: [semester.name])
        try await store.createFolder(path)
        return path
    }

    /// A first semester for a new vault, from today's date: from August to January the fall term
    /// (15 weeks from the first Monday on or after 1 September), otherwise the spring term (15
    /// weeks from the first Monday on or after 15 February). The user can change it afterwards.
    public static func suggestedSemester(today: LocalDate) -> NewSemester {
        let fall = today.month >= 8 || today.month == 1
        let year = today.month == 1 ? today.year - 1 : today.year
        let anchor: LocalDate = fall ? .literal(year, 9, 1) : .literal(year, 2, 15)
        let start = anchor.weekday == .monday ? anchor : anchor.startOfWeek.adding(days: 7)
        return NewSemester(name: "\(fall ? "Fall" : "Spring") \(year)", start: start, end: start.adding(days: 15 * 7 - 1))
    }
}
