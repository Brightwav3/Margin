import Foundation

/// Turns a `NewCourse` into the folder and `_course.md` of spec 05 §1 and §5 (M10-16.B).
///
/// The id is the slug of the name (numbered when taken), the folder is the name made safe as a file
/// name, the file is written by `SampleVaultGenerator.courseFile`, the same renderer the sample vault
/// uses, so a created course looks like every other one. The text is checked by `CourseValidator`
/// before anything is written.
struct CourseFactory {
    /// What creating the course will write.
    struct Plan: Sendable {
        var course: Course
        var semester: Semester
        /// `<semester>/<folder>`.
        var folder: VaultPath
        /// `<semester>/<folder>/_course.md`.
        var path: VaultPath
        var text: String
    }

    /// Plans the creation against the current semesters and courses.
    /// - Throws: `.invalid` (bad name, colour, session or a file that would not validate), `.notFound`
    ///   (no such semester), `.readOnly` (archived semester), `.conflict` (the folder exists).
    static func plan(_ new: NewCourse, semesters: [Semester], entries: [VaultCourseModel.Entry]) throws -> Plan {
        let name = try CourseWriting.requireName(new.name)
        guard let semester = semesters.first(where: { $0.id == new.semester }) else {
            throw MarginError.notFound("No semester \(new.semester)")
        }
        if semester.isArchived { throw MarginError.readOnly("\(semester.name) is archived and read-only") }
        let inSemester = entries.filter { $0.semesterFolder == semester.name }
        let folderName = VaultPath.filename(fromTitle: name)
        if inSemester.contains(where: { $0.folder.caseInsensitiveCompare(folderName) == .orderedSame }) {
            throw MarginError.conflict("\(semester.name)/\(folderName) already exists")
        }
        let id = CourseWriting.courseID(for: name, taken: Set(entries.map(\.course.id)))
        let course = try CourseWriting.makeCourse(new, id: id, name: name, usedColors: inSemester.map(\.course.style.color))
        let text = SampleVaultGenerator.courseFile(course)
        if let problem = CourseValidator.validate(text).first { throw problem }
        let folder = try VaultPath(components: [semester.name, folderName])
        return Plan(course: course, semester: semester, folder: folder, path: try folder.appending("_course.md"), text: text)
    }
}
