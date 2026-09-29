/// Visual identity of a course. Colours are `#RRGGBB` strings so the type stays UI-free;
/// `color` is the palette key stored in `_course.md` (`color: bio`).
public struct CourseStyle: Codable, Sendable, Hashable {
    /// Icon name as stored in the vault (`icon: eco`).
    public var icon: String
    /// Palette key (`bio`, `chem`, …).
    public var color: String
    /// Light tint used for chips and cards.
    public var background: String
    /// Text/icon colour on `background`.
    public var foreground: String
    /// Saturated dot / graph hub colour.
    public var dot: String

    public init(icon: String, color: String, background: String, foreground: String, dot: String) {
        self.icon = icon; self.color = color; self.background = background
        self.foreground = foreground; self.dot = dot
    }
}

/// One component of the grade (`grading: - {label: Midterm, weight: 25%}`).
public struct GradingPart: Codable, Sendable, Hashable {
    public var label: String
    /// Percentage of the final grade, 0…100.
    public var weightPercent: Int

    public init(label: String, weightPercent: Int) {
        self.label = label; self.weightPercent = weightPercent
    }
}

/// A course (`_course.md`). `id` is stable and never changes on rename.
///
/// Invariants: `sessions` and `exams` all carry this course's `id`; `grading` weights sum to
/// 100 when non-empty (not enforced, the vault may be hand-edited).
public struct Course: Codable, Sendable, Hashable, Identifiable {
    public let id: CourseID
    public var semester: SemesterID
    public var name: String
    public var code: String
    public var professor: String?
    public var room: String?
    public var faculty: String?
    public var credits: Int?
    public var style: CourseStyle
    public var sessions: [Session]
    public var exams: [Exam]
    public var grading: [GradingPart]

    public init(
        id: CourseID, semester: SemesterID, name: String, code: String,
        professor: String? = nil, room: String? = nil, faculty: String? = nil, credits: Int? = nil,
        style: CourseStyle, sessions: [Session] = [], exams: [Exam] = [], grading: [GradingPart] = []
    ) {
        self.id = id; self.semester = semester; self.name = name; self.code = code
        self.professor = professor; self.room = room; self.faculty = faculty; self.credits = credits
        self.style = style; self.sessions = sessions; self.exams = exams; self.grading = grading
    }
}
