import Foundation
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

/// Details of an existing course that `CourseCatalogWriter.update` changes (course settings).
/// `nil` leaves a field as it is. An empty string clears `professor`, `room` and `faculty`;
/// `credits: 0` clears the credits. `sessions` and `exams`, when given, replace the whole weekly
/// timetable or exam list (an empty list removes it).
public struct CourseUpdate: Codable, Sendable, Hashable {
    public var code: String?
    public var professor: String?
    public var room: String?
    public var faculty: String?
    public var credits: Int?
    public var sessions: [NewSession]?
    public var exams: [NewExam]?

    public init(code: String? = nil, professor: String? = nil, room: String? = nil, faculty: String? = nil,
                credits: Int? = nil, sessions: [NewSession]? = nil, exams: [NewExam]? = nil) {
        self.code = code; self.professor = professor; self.room = room; self.faculty = faculty
        self.credits = credits; self.sessions = sessions; self.exams = exams
    }
}

/// One exam of a `CourseUpdate` (an `Exam` before it belongs to a course).
public struct NewExam: Codable, Sendable, Hashable {
    public var title: String
    public var date: LocalDate
    public var time: LocalTime?
    /// Share of the final grade, 0–100.
    public var weightPercent: Int

    public init(title: String, date: LocalDate, time: LocalTime? = nil, weightPercent: Int = 0) {
        self.title = title; self.date = date; self.time = time; self.weightPercent = weightPercent
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
/// - **Course settings:** `update` changes only the keys its `CourseUpdate` names. Sessions get the
///   same checks as in `create` (length over 0 and at most 12 hours, no two at the same day and time);
///   an exam needs a title and a weight of 0–100.
/// - **One course archived or deleted:** `setArchived(course:)` moves the course folder to
///   `_archive/<semester>/` (and back); the course leaves `CourseCatalog.courses` and `sessions(week:)`,
///   is listed by `CourseCatalog.archivedCourses()` and is read-only until restored. `delete` moves the
///   course folder with all its notes to the trash (never hard-deleted); the course is gone from the
///   catalog. Both throw `.readOnly` in an archived semester (restore the semester instead).
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

    /// Changes the course's details (code, lecturer, room, faculty, credits, timetable, exams).
    /// An update that changes nothing returns an empty `ChangeSet`.
    func update(id: CourseID, _ update: CourseUpdate, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet

    /// Archives (`true`) or restores (`false`) one course: its folder moves to `_archive/<semester>/`.
    /// Doing what is already the case changes nothing (empty `ChangeSet`).
    func setArchived(course id: CourseID, _ archived: Bool, actor: Actor, baseVersion: String?,
                     dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet

    /// Moves the course folder, with its notes and files, to the trash. The `ChangeSet` has one
    /// `.deleted` entry (`_course.md`).
    func delete(id: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet

    /// Archives (`true`) or restores (`false`) a whole semester: its folder moves to `_archive/` and it
    /// becomes read-only. Doing what is already the case changes nothing (empty `ChangeSet`).
    func setArchived(semester: SemesterID, _ archived: Bool, actor: Actor, baseVersion: String?,
                     dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet

    /// Changes or cancels one occurrence of a weekly session.
    func override(session: SessionOverride, actor: Actor, baseVersion: String?, dryRun: Bool,
                  idempotencyKey: String?) async throws -> ChangeSet

    /// Sets the banner image of a course, or removes it (`nil`, to the trash). The image must be a PNG,
    /// JPEG, GIF or WebP of at most 5 MB (`.invalid` otherwise); a banner of another format replaces
    /// the old file. `baseVersion` is the `afterHash` of the banner being replaced (`.conflict` when
    /// it changed). Entries: the banner file `.created`/`.modified`/`.deleted` (plus `.deleted` for a
    /// replaced file of another format). Removing a banner that is not there: empty `ChangeSet`.
    func setBanner(_ image: Data?, course: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
                   idempotencyKey: String?) async throws -> ChangeSet

    /// Removes the override of the occurrence again (no-op, empty `ChangeSet`, when there is none).
    func clearOverride(sessionID: String, course: CourseID, originalDate: LocalDate, actor: Actor,
                       baseVersion: String?, dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet
}
