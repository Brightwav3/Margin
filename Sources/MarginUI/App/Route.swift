import MarginCore

/// What a tab shows. Stored in `ShellTab.route` as a string key so tabs stay plain values.
public enum Route: Hashable, Sendable {
    case courses
    case course(CourseID)
    case note(NoteID)
    /// A class without a note yet: the editor opens empty and the note is created on first write.
    case draft(course: CourseID, date: LocalDate, title: String)
    case inbox
    case today
    case upcoming
    case graph
    case search(String)
    case grades
    case archive
    case settings

    public var key: String {
        switch self {
        case .courses: "courses"
        case .course(let id): "course/\(id)"
        case .note(let id): "note/\(id)"
        case .draft(let course, let date, let title): "draft/\(course)/\(date.iso)/\(title)"
        case .inbox: "inbox"
        case .today: "today"
        case .upcoming: "upcoming"
        case .graph: "graph"
        case .search(let q): "search/\(q)"
        case .grades: "grades"
        case .archive: "archive"
        case .settings: "settings"
        }
    }

    public init?(key: String) {
        let parts = key.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let head = parts[0], rest = parts.count > 1 ? parts[1] : ""
        switch head {
        case "courses": self = .courses
        case "course" where !rest.isEmpty: self = .course(rest)
        case "note" where !rest.isEmpty: self = .note(rest)
        case "draft":
            let p = rest.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 3, let date = LocalDate(iso: p[1]) else { return nil }
            self = .draft(course: p[0], date: date, title: p[2])
        case "inbox": self = .inbox
        case "today": self = .today
        case "upcoming": self = .upcoming
        case "graph": self = .graph
        case "search": self = .search(rest)
        case "grades": self = .grades
        case "archive": self = .archive
        case "settings": self = .settings
        default: return nil
        }
    }

    /// Notes and drafts live in tabs; everything else is a place.
    public var isNote: Bool {
        switch self {
        case .note, .draft: true
        default: false
        }
    }

    /// Rail entry that lights up for this route.
    var railID: String {
        switch self {
        case .courses, .search, .grades, .archive, .settings, .graph: "home"
        case .course(let id): id
        case .draft(let course, _, _): course
        case .note: "home"
        case .inbox: "inbox"
        case .today: "today"
        case .upcoming: "upcoming"
        }
    }
}
