/// Visual emphasis of a due chip. Plain domain data; the UI maps it to colours.
public enum DueChipTone: String, Codable, Sendable, Hashable {
    /// Red: overdue, due today, exams.
    case danger
    /// Amber: due soon.
    case warning
    /// Grey: not urgent.
    case neutral
}

/// Text and tone of a due chip (`Today`, `Due Fri`, `Exam Thu`, `Overdue 2d`).
public struct DueChip: Codable, Sendable, Hashable {
    public var text: String
    public var tone: DueChipTone
    public init(text: String, tone: DueChipTone) { self.text = text; self.tone = tone }
}

/// Maps `DueLabel` (API, relative distance) to the chip text of the mockups
/// (`docs/design/mockups/Margin.dc.html`: `Today`, `Tomorrow`, `Due Fri`, `Exam`).
///
/// Rules (tasks / exams):
/// - overdue: `Overdue 2d` red / `Exam passed` grey
/// - today: `Today` red / `Exam today` red
/// - tomorrow: `Tomorrow` amber / `Exam tomorrow` red
/// - 2...6 days: `Due Fri` amber / `Exam Thu` red
/// - 7+ days: `Due 12 Oct` grey / `Exam 15 Oct` amber
public enum DueLabelRules {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// Chip for `label`.
    public static func chip(for label: DueLabel, kind: TaskKind = .task) -> DueChip {
        let exam = kind == .exam
        switch label {
        case .overdue(let days):
            return exam ? DueChip(text: "Exam passed", tone: .neutral)
                        : DueChip(text: "Overdue \(days)d", tone: .danger)
        case .today:
            return DueChip(text: exam ? "Exam today" : "Today", tone: .danger)
        case .tomorrow:
            return exam ? DueChip(text: "Exam tomorrow", tone: .danger)
                        : DueChip(text: "Tomorrow", tone: .warning)
        case .weekday(let wd):
            return exam ? DueChip(text: "Exam \(wd.rawValue)", tone: .danger)
                        : DueChip(text: "Due \(wd.rawValue)", tone: .warning)
        case .date(let d):
            let day = "\(d.day) \(months[max(0, min(11, d.month - 1))])"
            return exam ? DueChip(text: "Exam \(day)", tone: .warning)
                        : DueChip(text: "Due \(day)", tone: .neutral)
        }
    }

    /// Chip for a due date relative to `today`.
    public static func chip(due: LocalDate, today: LocalDate, kind: TaskKind = .task) -> DueChip {
        chip(for: DueLabel.make(due: due, today: today), kind: kind)
    }
}
