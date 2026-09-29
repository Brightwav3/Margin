/// What the "new course" dialog collects (M10-16). Everything but `name` and `semester` is optional.
///
/// `id`, folder name and `_course.md` are derived by the writer: the id is the slug of `name` (a
/// number is appended when the slug is taken), the folder is `name` made safe as a file name.
public struct NewCourse: Codable, Sendable, Hashable {
    public var name: String
    /// The semester the course belongs to (`Semester.id`).
    public var semester: SemesterID
    public var code: String
    public var professor: String?
    public var room: String?
    public var faculty: String?
    public var credits: Int?
    /// Icon name (`eco`). `nil`: `school`.
    public var icon: String?
    /// Palette key (`bio`). `nil`: the next palette key not used by another course of the semester.
    public var color: String?
    /// The weekly timetable. Empty: the default schedule, one 90 minute lecture on Monday at 10:00.
    public var sessions: [NewSession]

    public init(name: String, semester: SemesterID, code: String = "", professor: String? = nil, room: String? = nil,
                faculty: String? = nil, credits: Int? = nil, icon: String? = nil, color: String? = nil,
                sessions: [NewSession] = []) {
        self.name = name; self.semester = semester; self.code = code; self.professor = professor
        self.room = room; self.faculty = faculty; self.credits = credits; self.icon = icon
        self.color = color; self.sessions = sessions
    }
}

/// One weekly class of a `NewCourse` (a `Session` before the course has an id).
public struct NewSession: Codable, Sendable, Hashable {
    public var day: Weekday
    public var start: LocalTime
    /// Duration in hours, greater than 0 and at most 12.
    public var lengthHours: Double
    public var kind: String
    public var room: String?

    public init(day: Weekday, start: LocalTime, lengthHours: Double = 1.5, kind: String = "Lecture", room: String? = nil) {
        self.day = day; self.start = start; self.lengthHours = lengthHours; self.kind = kind; self.room = room
    }
}

/// Creating and editing courses, archiving semesters and changing single classes (M10). The read side
/// is `CourseCatalog`; after a write, `CourseCatalog.courses`, `course(id:)`, `sessions(week:)`,
/// `semesters()` and `updates` already show the change.
///
/// Implementations: `FixtureCourseCatalogWriter` (in memory) and `VaultCourseCatalogWriter` (edits
/// `_course.md` and folders). Rules both obey, checked by
/// `Tests/Conformance/CourseCatalogWriterConformanceTests.swift`:
///
/// - **Write context (contract rule 0):** every method takes `actor`, `baseVersion`, `dryRun` and
///   `idempotencyKey` and returns a `ChangeSet`. `baseVersion` is the value of `courseVersion(id:)`
///   (the hash of the course's `_course.md`); a stale one throws `.conflict`. `create` and
///   `setArchived` ignore `baseVersion` (nothing exists yet, or the target is a folder). A dry run
///   returns the `ChangeSet` the write would produce and changes nothing. A repeated
///   `(actor, idempotencyKey)` returns the first result and writes nothing.
/// - **Lossless:** an edit changes only the keys it names in `_course.md`; other keys, their order,
///   comments and the body stay byte for byte.
/// - **Ids are stable:** renaming a course never changes its `CourseID`.
/// - **Archived semesters are read-only:** `create` in, and every course edit of, an archived semester
///   throws `.readOnly`, and so does creating or moving a note into one (`NoteRepository`).
///   `setArchived(false)` makes it writable again and restores everything as it was.
/// - **Overrides:** `override(session:)` changes or cancels one occurrence of a weekly session.
///   `CourseCatalog.sessions(week:)` returns cancelled occurrences with `isCancelled` set and moved ones
///   at their new date, time and room (`SessionOccurrence`). An override replaces an earlier one for the
///   same session and date.
/// - **Errors:** unknown course, semester or session is `.notFound`; an empty name, a bad palette
///   key, an override that changes nothing or whose date is not the session's weekday is `.invalid`;
///   an existing folder is `.conflict`.
public protocol CourseCatalogWriter: Sendable {
    /// The version of a course for `baseVersion`. Throws `.notFound` for an unknown course.
    func courseVersion(id: CourseID) async throws -> String

    /// Creates a course: folder, `_course.md` and, with no sessions given, the default schedule.
    /// The `ChangeSet` has one `.created` entry (`_course.md`).
    func create(_ course: NewCourse, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet

    /// Renames a course (`name:` in `_course.md`). With `renameFolder` the folder is renamed to
    /// match, and links to notes in it are rewritten; `.conflict` when the new folder exists.
    func rename(id: CourseID, to name: String, renameFolder: Bool, actor: Actor, baseVersion: String?,
                dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet

    /// Sets the icon and/or palette key of a course; `nil` leaves that part as it is.
    func setStyle(id: CourseID, icon: String?, color: String?, actor: Actor, baseVersion: String?,
                  dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet

    /// Archives (`true`) or restores (`false`) a whole semester: its folder moves to `_archive/` and it
    /// becomes read-only. Doing what is already the case changes nothing (empty `ChangeSet`).
    func setArchived(semester: SemesterID, _ archived: Bool, actor: Actor, baseVersion: String?,
                     dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet

    /// Changes or cancels one occurrence of a weekly session.
    func override(session: SessionOverride, actor: Actor, baseVersion: String?, dryRun: Bool,
                  idempotencyKey: String?) async throws -> ChangeSet

    /// Removes the override of the occurrence again (no-op, empty `ChangeSet`, when there is none).
    func clearOverride(sessionID: String, course: CourseID, originalDate: LocalDate, actor: Actor,
                       baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet
}
