/// What the "new semester" dialog collects (M11-05).
///
/// `name` is also the folder name (`Fall 2026`); the id is its slug (`fall-2026`).
public struct NewSemester: Codable, Sendable, Hashable {
    public var name: String
    /// First day of week 1; must be a Monday.
    public var start: LocalDate
    /// Last day of the term (inclusive), not before `start`.
    public var end: LocalDate
    /// Weeks without teaching (1-based, within the term).
    public var breakWeeks: [Int]

    public init(name: String, start: LocalDate, end: LocalDate, breakWeeks: [Int] = []) {
        self.name = name; self.start = start; self.end = end; self.breakWeeks = breakWeeks
    }
}

/// A change to a semester; `nil` leaves that part as it is.
public struct SemesterUpdate: Codable, Sendable, Hashable {
    public var name: String?
    public var start: LocalDate?
    public var end: LocalDate?
    public var breakWeeks: [Int]?

    public init(name: String? = nil, start: LocalDate? = nil, end: LocalDate? = nil, breakWeeks: [Int]? = nil) {
        self.name = name; self.start = start; self.end = end; self.breakWeeks = breakWeeks
    }
}

/// Creating, editing and removing semesters (M11-05.B). The read side is `CourseCatalog.semesters()`;
/// after a write it already shows the change.
///
/// Implementations: `FixtureSemesterStore` (in memory) and `VaultSemesterStore` (the array in
/// `.margin/semesters.json`, and the semester folder). Rules both obey, checked by
/// `Tests/Conformance/SemesterStoreConformanceTests.swift`:
///
/// - **Write context (contract rule 0):** every write takes `actor`, `baseVersion`, `dryRun` and
///   `idempotencyKey` and returns a `ChangeSet`. `baseVersion` is `version()`; a stale one throws
///   `.conflict`. A dry run returns the `ChangeSet` the write would produce and changes nothing. A
///   repeated `(actor, idempotencyKey)` returns the first result and writes nothing.
/// - **Validation (`.invalid`):** the name is not empty, is usable as a folder name, and does not
///   start with `_` or `.`; `start` is a Monday; `end` is not before `start`; every break week is
///   within `1...weekCount` (duplicates are dropped, the list is sorted).
/// - **Unique:** a name (compared without case) or id that another semester has is `.conflict`.
/// - **Create:** the id is the slug of the name. The `ChangeSet` has an entry for
///   `.margin/semesters.json`.
/// - **Update:** renaming also renames the folder and gives the semester the slug of the new name as
///   its id; the ids of its courses stay. Changing only dates or break weeks touches
///   `semesters.json` alone. An update that changes nothing is an empty `ChangeSet`.
/// - **Delete:** removes the semester from `semesters.json`. A semester that still has courses is
///   `.conflict`; files are never deleted.
/// - **Archived semesters are read-only:** `update` and `delete` throw `.readOnly`.
/// - **Current semester:** `current()` is the non-archived semester that contains today's date
///   (`Clock`), else the latest one that started, else the earliest; `nil` when there is none.
/// - **Errors:** an unknown id is `.notFound`.
public protocol SemesterStore: Sendable {
    /// All semesters, oldest start first.
    func semesters() async throws -> [Semester]

    /// The semester that is "now" by the clock, never an archived one.
    func current() async throws -> Semester?

    /// The `baseVersion` of semester writes (changes with every write to the semester list).
    func version() async throws -> String

    func create(_ semester: NewSemester, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet

    func update(id: SemesterID, _ update: SemesterUpdate, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet

    func delete(id: SemesterID, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet
}
