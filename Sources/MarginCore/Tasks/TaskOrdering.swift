/// Sort order of due items: due date (undated last), course id, item id.
enum TaskOrdering {
    static func dueOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        let (x, y) = (a.due ?? .literal(9999, 12, 31), b.due ?? .literal(9999, 12, 31))
        if x != y { return x < y }
        let (c, d) = (a.source.courseID ?? "", b.source.courseID ?? "")
        return c != d ? c < d : a.id < b.id
    }

    static func relabel(_ item: TaskItem, today: LocalDate) -> TaskItem {
        var t = item
        t.label = item.due.map { DueLabel.make(due: $0, today: today) }
        return t
    }
}
