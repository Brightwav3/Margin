import Testing
@testable import MarginCore

@Suite struct DueLabelRulesTests {
    // Today is Monday 2026-09-28.
    static let today = LocalDate.literal(2026, 9, 28)

    // (due, kind, text, tone): exactly 20 cases.
    static let table: [(LocalDate, TaskKind, String, DueChipTone)] = [
        (.literal(2026, 9, 21), .task, "Overdue 7d", .danger),
        (.literal(2026, 9, 26), .task, "Overdue 2d", .danger),
        (.literal(2026, 9, 27), .task, "Overdue 1d", .danger),
        (.literal(2026, 9, 28), .task, "Today", .danger),
        (.literal(2026, 9, 29), .task, "Tomorrow", .warning),
        (.literal(2026, 9, 30), .task, "Due Wed", .warning),
        (.literal(2026, 10, 2), .task, "Due Fri", .warning),
        (.literal(2026, 10, 4), .task, "Due Sun", .warning),
        (.literal(2026, 10, 5), .task, "Due 5 Oct", .neutral),
        (.literal(2026, 12, 11), .task, "Due 11 Dec", .neutral),
        (.literal(2027, 1, 3), .task, "Due 3 Jan", .neutral),
        (.literal(2026, 9, 1), .exam, "Exam passed", .neutral),
        (.literal(2026, 9, 27), .exam, "Exam passed", .neutral),
        (.literal(2026, 9, 28), .exam, "Exam today", .danger),
        (.literal(2026, 9, 29), .exam, "Exam tomorrow", .danger),
        (.literal(2026, 10, 1), .exam, "Exam Thu", .danger),
        (.literal(2026, 10, 4), .exam, "Exam Sun", .danger),
        (.literal(2026, 10, 5), .exam, "Exam 5 Oct", .warning),
        (.literal(2026, 12, 11), .exam, "Exam 11 Dec", .warning),
        (.literal(2028, 2, 29), .task, "Due 29 Feb", .neutral),
    ]

    @Test func tableHasTwentyCases() { #expect(Self.table.count == 20) }

    @Test(arguments: table)
    func chipMatches(due: LocalDate, kind: TaskKind, text: String, tone: DueChipTone) {
        let chip = DueLabelRules.chip(due: due, today: Self.today, kind: kind)
        #expect(chip == DueChip(text: text, tone: tone))
    }
}
