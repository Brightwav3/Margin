import MarginCore
import SwiftUI

/// Task row (M7-04, **proposal**: the mockups have no task list screen): checkbox, text, course
/// chip, weight, due label (red for overdue, today and tomorrow) and the note it comes from.
public struct TaskRow: View {
    let task: TaskItem
    var course: Course?
    var weight: String?
    /// Replaces the due label („Graded 18/20“).
    var status: String?
    var from: String?
    var onToggle: () -> Void = {}
    var onOpenSource: (() -> Void)?
    @State private var hovered = false

    public init(task: TaskItem, course: Course? = nil, weight: String? = nil, status: String? = nil,
                from: String? = nil, onToggle: @escaping () -> Void = {}, onOpenSource: (() -> Void)? = nil) {
        self.task = task
        self.course = course
        self.weight = weight
        self.status = status
        self.from = from
        self.onToggle = onToggle
        self.onOpenSource = onOpenSource
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if task.kind == .exam {
                Icon("quiz", size: 16, color: MarginColor.due).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            } else {
                CheckboxView(isOn: Binding(get: { task.done }, set: { _ in onToggle() }), label: task.text)
                    .accessibilityIdentifier("task-\(task.text)")
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(task.text)
                    .marginFont(MarginTextSize.base)
                    .strikethrough(task.done, color: MarginColor.textTertiary)
                    .foregroundStyle(task.done ? MarginColor.textTertiary : MarginColor.ink)
                if let from {
                    Button { onOpenSource?() } label: {
                        HStack(spacing: 4) {
                            Icon("description", size: 13, color: MarginColor.textTertiary)
                            Text(from).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpenSource == nil)
                    .help("Open the note at this task")
                }
            }
            Spacer(minLength: 8)
            if let course {
                HStack(spacing: 6) {
                    Circle().fill(Color(hexString: course.style.dot)).frame(width: 7, height: 7)
                    Text(course.code).marginFont(MarginTextSize.xs)
                }
                .foregroundStyle(Color(hexString: course.style.foreground))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Color(hexString: course.style.background), in: Capsule())
            }
            if let weight {
                Text(weight).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary).monospacedDigit()
            }
            Text(status ?? DueFormat.label(task.label, due: task.due))
                .marginFont(MarginTextSize.sm)
                .foregroundStyle(status == nil && DueFormat.isUrgent(task.label) && !task.done ? MarginColor.due
                                                                                               : MarginColor.textSecondary)
                .frame(minWidth: 72, alignment: .trailing)
                .modifier(DueTooltip(task: task, status: status, from: from))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(hovered ? MarginColor.hover : .clear, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// 3b: the exact due date and where it comes from.
private struct DueTooltip: ViewModifier {
    let task: TaskItem
    let status: String?
    let from: String?

    func body(content: Content) -> some View {
        if let due = task.due, status == nil {
            let title = "\(task.kind == .exam ? "Exam" : "Due") \(CoursesFormat.weekday(due.weekday)) \(due.day) \(CoursesFormat.month(due.month))"
            let detail = from.map { "Written in \($0). Change the @date there, or right-click the task." }
            content.marginTooltip(title, detail: detail, placement: .bottom)
        } else {
            content
        }
    }
}

/// Due labels („Due Fri“, „Today“, „Exam“) — M7-08.
public enum DueFormat {
    public static func label(_ label: DueLabel?, due: LocalDate?) -> String {
        switch label {
        case .overdue(let days)?: days == 1 ? "Yesterday" : "\(days) days late"
        case .today?: "Today"
        case .tomorrow?: "Tomorrow"
        case .weekday(let d)?: "Due \(CoursesFormat.weekday(d))"
        case .date(let d)?: "\(d.day) \(CoursesFormat.month(d.month))"
        case nil: due.map { "\($0.day) \(CoursesFormat.month($0.month))" } ?? ""
        }
    }

    /// Red: overdue, today, tomorrow.
    public static func isUrgent(_ label: DueLabel?) -> Bool {
        switch label {
        case .overdue?, .today?, .tomorrow?: true
        default: false
        }
    }
}
