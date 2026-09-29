import Foundation

/// The rules of `SemesterStore` that both implementations share: validation, ids, versions and the
/// JSON of `.margin/semesters.json`.
enum SemesterRules {
    static func slug(_ name: String) -> SemesterID { VaultCourseModel.semesterID(name) }

    /// Trims and checks a name (see `SemesterStore`, "Validation").
    static func requireName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MarginError.invalid("A semester needs a name") }
        guard !name.hasPrefix("_"), !name.hasPrefix("."), VaultPath.filename(fromTitle: name) == name,
              !slug(name).isEmpty
        else { throw MarginError.invalid("\"\(name)\" cannot be a semester name (it is the folder name)") }
        return name
    }

    /// Checks dates and break weeks; returns the break weeks sorted and without duplicates.
    static func requireTerm(start: LocalDate, end: LocalDate, breakWeeks: [Int]) throws -> [Int] {
        guard start.weekday == .monday else { throw MarginError.invalid("A semester starts on a Monday, not \(start)") }
        guard end >= start else { throw MarginError.invalid("A semester cannot end (\(end)) before it starts (\(start))") }
        let weeks = Semester(id: "x", name: "x", start: start, end: end).weekCount
        for w in breakWeeks where !(1...weeks).contains(w) {
            throw MarginError.invalid("Break week \(w) is outside the semester (1…\(weeks))")
        }
        return Array(Set(breakWeeks)).sorted()
    }

    /// `.conflict` when another semester has this name or id.
    static func requireUnique(name: String, id: SemesterID, among others: [Semester]) throws {
        if let clash = others.first(where: { $0.id == id || $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw MarginError.conflict("Semester \(clash.name) already exists")
        }
    }

    static func make(_ new: NewSemester, among existing: [Semester]) throws -> Semester {
        let name = try requireName(new.name)
        let weeks = try requireTerm(start: new.start, end: new.end, breakWeeks: new.breakWeeks)
        let id = slug(name)
        try requireUnique(name: name, id: id, among: existing)
        return Semester(id: id, name: name, start: new.start, end: new.end, breakWeeks: weeks)
    }

    /// The semester after `update`. `others` are the other semesters (for uniqueness).
    static func apply(_ update: SemesterUpdate, to old: Semester, among others: [Semester]) throws -> Semester {
        if old.isArchived { throw MarginError.readOnly("\(old.name) is archived and read-only") }
        var name = old.name, id = old.id
        if let requested = update.name {
            name = try requireName(requested)
            if name != old.name {
                id = slug(name)
                try requireUnique(name: name, id: id, among: others)
            }
        }
        let start = update.start ?? old.start, end = update.end ?? old.end
        let weeks = try requireTerm(start: start, end: end, breakWeeks: update.breakWeeks ?? old.breakWeeks)
        let new = Semester(id: id, name: name, start: start, end: end, breakWeeks: weeks)
        return new
    }

    static func sorted(_ list: [Semester]) -> [Semester] { list.sorted { ($0.start, $0.id) < ($1.start, $1.id) } }

    static func current(_ list: [Semester], today: LocalDate) -> Semester? {
        ServiceRules.currentSemester(list.filter { !$0.isArchived }, today: today)
    }

    static func json(_ list: [Semester]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: (try? encoder.encode(list)) ?? Data("[]".utf8), as: UTF8.self) + "\n"
    }

    static func version(of list: [Semester]) -> String { ContentHash(of: json(list)).hex }
}
