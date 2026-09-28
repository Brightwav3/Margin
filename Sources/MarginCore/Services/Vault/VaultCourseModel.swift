import Foundation

/// Courses and semesters read from a vault: `Fall 2026/<Course>/_course.md` (spec 05 §5) and
/// `.margin/semesters.json`. Immutable snapshot; the backend replaces it when a `_course.md`
/// changes.
struct VaultCourseModel: Sendable {
    /// A course and where it lives.
    struct Entry: Sendable {
        var course: Course
        /// Semester folder (`Fall 2026`) and course folder (`Cell Biology`).
        var semesterFolder: String
        var folder: String
    }

    var semesters: [Semester] = []
    var entries: [Entry] = []

    var courses: [Course] { entries.map(\.course) }

    func entry(_ id: CourseID) -> Entry? { entries.first { $0.course.id == id } }

    /// The course of a note record: by its `<semester>/<course>` folders, else by `class:` name.
    func courseID(semesterFolder: String?, folder: String?, className: String?) -> CourseID? {
        if let semesterFolder, let folder,
           let e = entries.first(where: { $0.semesterFolder == semesterFolder && $0.folder == folder }) {
            return e.course.id
        }
        if let className {
            return entries.first { $0.course.name.caseInsensitiveCompare(className) == .orderedSame }?.course.id
        }
        return nil
    }

    // MARK: Loading

    /// Reads the model. Unreadable or malformed files are skipped (a hand-edited vault must never
    /// stop the app); the first course with an id wins.
    static func load(from store: VaultStore, clock: any Clock) async -> VaultCourseModel {
        var model = VaultCourseModel()
        let paths = (try? await store.list()) ?? []
        var seen = Set<CourseID>()
        for path in paths {
            let parts = path.components
            guard parts.count == 3, parts[2] == "_course.md", !parts[0].hasPrefix("_"), !parts[0].hasPrefix("."),
                  let text = try? await store.read(path).content
            else { continue }
            let (fm, _) = Frontmatter.parse(text)
            guard let fm, let course = parseCourse(fm, semesterFolder: parts[0], folder: parts[1]),
                  seen.insert(course.id).inserted
            else { continue }
            model.entries.append(Entry(course: course, semesterFolder: parts[0], folder: parts[1]))
        }
        model.semesters = await loadSemesters(store: store, folders: Array(Set(model.entries.map(\.semesterFolder))), clock: clock)
        return model
    }

    /// `.margin/semesters.json` when present; otherwise one semester per semester folder, starting
    /// with the current week and lasting 15 weeks (a placeholder until the user sets dates).
    private static func loadSemesters(store: VaultStore, folders: [String], clock: any Clock) async -> [Semester] {
        var result: [Semester] = []
        if let path = try? VaultPath(".margin/semesters.json"), let data = try? await store.readData(path).data,
           let decoded = try? JSONDecoder().decode([Semester].self, from: data) {
            result = decoded
        }
        for folder in folders.sorted() where !result.contains(where: { $0.name == folder || $0.id == semesterID(folder) }) {
            let start = clock.today.startOfWeek
            result.append(Semester(id: semesterID(folder), name: folder, start: start, end: start.adding(days: 15 * 7 - 1)))
        }
        return result.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    static func semesterID(_ folder: String) -> SemesterID { NoteIndex.slug(folder) }

    // MARK: Parsing `_course.md`

    static func parseCourse(_ fm: Frontmatter, semesterFolder: String, folder: String) -> Course? {
        let name = fm.string(for: "name") ?? folder
        var course = Course(
            id: fm.string(for: "id") ?? NoteIndex.slug(folder),
            semester: semesterID(semesterFolder), name: name, code: fm.string(for: "code") ?? "",
            professor: fm.string(for: "professor"), room: fm.string(for: "room"), faculty: fm.string(for: "faculty"),
            credits: fm.number(for: "credits").map { Int($0.rounded()) },
            style: CoursePalette.style(icon: fm.string(for: "icon") ?? "", color: fm.string(for: "color") ?? ""))
        let id = course.id

        for item in fm.list(for: "sessions") ?? [] {
            guard let day = item["day"]?.stringValue.flatMap({ Weekday(token: $0) }),
                  let start = item["time"]?.stringValue.flatMap({ LocalTime(string: $0) })
            else { continue }
            let length = item["length"]?.numberValue ?? 1
            guard length > 0 else { continue }
            course.sessions.append(Session(courseID: id, day: day, start: start, lengthHours: length,
                                           kind: item["kind"]?.stringValue ?? "Lecture", room: item["room"]?.stringValue))
        }
        for item in fm.list(for: "exams") ?? [] {
            guard let title = item["title"]?.stringValue, let date = item["date"]?.dateValue else { continue }
            course.exams.append(Exam(courseID: id, title: title, date: date,
                                     time: item["time"]?.stringValue.flatMap { LocalTime(string: $0) },
                                     weightPercent: percent(item["weight"]) ?? 0))
        }
        for item in fm.list(for: "grading") ?? [] {
            guard let label = item["label"]?.stringValue else { continue }
            course.grading.append(GradingPart(label: label, weightPercent: percent(item["weight"]) ?? 0))
        }
        return course
    }

    /// `25%`, `25` and `25.0` all read as 25.
    static func percent(_ value: FrontmatterValue?) -> Int? {
        switch value {
        case .number(let d)?: return Int(d.rounded())
        case .string(let s)?:
            let t = s.hasSuffix("%") ? String(s.dropLast()) : s
            return Double(t.trimmingCharacters(in: .whitespaces)).map { Int($0.rounded()) }
        default: return nil
        }
    }
}
