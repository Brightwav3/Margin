import Foundation
/// A change to the set of courses, delivered by `CourseCatalog.updates`.
public struct CatalogUpdate: Codable, Sendable, Hashable {
    /// Courses that were added, changed or removed, sorted.
    public var courses: [CourseID]

    public init(courses: [CourseID]) { self.courses = courses.sorted() }
}

/// Courses, semesters and the weekly timetable (read side; creating and editing courses is
/// `CourseCatalogWriter`, M10).
///
/// Implementations: `FixtureCourseCatalog` (in memory, `Fixtures.week5`) and `VaultCourseCatalog`
/// (reads `_course.md` files). Both obey the same observable rules, checked by
/// `Tests/Conformance/CourseCatalogConformanceTests.swift`:
///
/// - **Ordering:** `courses(query:)` is sorted by name, case-insensitively, then by id.
///   `sessions(week:)` is sorted by date, start time, then course id.
/// - **Errors:** `course(id:)` throws `MarginError.notFound` for an unknown id;
///   `sessions(week:)` throws `.invalid` for a week outside the current semester.
/// - **Updates:** `updates` yields after courses changed behind the app's back.
public protocol CourseCatalog: Sendable {
    /// All known semesters, oldest first.
    func semesters() async throws -> [Semester]

    /// Courses of the current semester (the one containing today, else the latest), optionally
    /// filtered by `query`: a case-insensitive substring of name, code or professor. `nil` or an
    /// empty query returns all courses.
    func courses(query: String?) async throws -> [Course]

    /// Courses archived one by one (`CourseCatalogWriter.setArchived(course:)`) in semesters that are
    /// not archived themselves, sorted by name. Courses of an archived semester are not listed here.
    func archivedCourses() async throws -> [Course]

    /// The banner image of a course (PNG, JPEG, GIF or WebP bytes), or `nil` when it has none.
    /// Stored as `<course folder>/_files/banner.<ext>` (vault spec 05 §1). Unknown course: `.notFound`.
    func banner(course: CourseID) async throws -> Data?

    /// One course. Throws `MarginError.notFound` for an unknown id.
    func course(id: CourseID) async throws -> Course

    /// The classes of a 1-based week of the current semester, one per weekly session.
    func sessions(week: Int) async throws -> [SessionOccurrence]

    /// A new stream on every access. Each element says which courses changed. The stream stays
    /// open until the consumer stops iterating.
    var updates: AsyncStream<CatalogUpdate> { get }
}
