import Foundation
@testable import MarginCore

enum TaskQueryTestSupport {
    static func item(_ id: String, due: LocalDate?, done: Bool = false, course: CourseID? = "bio",
                     kind: TaskKind = .task) -> TaskItem {
        TaskItem(id: id, text: "Text of \(id)", due: due, label: nil, done: done, kind: kind,
                 source: TaskLocation(noteID: "\(course ?? "x")/notes", line: 1, courseID: course))
    }

    static func exam(_ id: String, due: LocalDate, course: CourseID = "bio") -> TaskItem {
        item(id, due: due, course: course, kind: .exam)
    }

    static func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { .literal(y, m, d) }

    static func zone(_ id: String) throws -> TimeZone {
        guard let z = TimeZone(identifier: id) else { throw MarginError.invalid("No time zone \(id)") }
        return z
    }

    /// An instant from `2026-10-25T22:59:59Z`.
    static func instant(_ iso: String) throws -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: iso) else { throw MarginError.invalid("Bad date \(iso)") }
        return d
    }

    static func clock(_ iso: String, in zone: String) throws -> FixedClock {
        FixedClock(now: try instant(iso), timeZone: try Self.zone(zone))
    }
}
