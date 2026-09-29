import Foundation

/// One card of the course gallery (mockup 2c, M4-08): a class, titled by kind, number and theme
/// ("Lecture 9 · Membrane transport", "Tue 29 Sep"), with the note behind it.
///
/// Invariants: `note.courseID == courseID`; `isNotStarted == note.isPlaceholder`; for a card that
/// comes from the timetable `session` is set and `start` is that session's start.
public struct CourseCard: Codable, Sendable, Hashable, Identifiable {
    /// `<session id>@<date>` for a class of the timetable, the note id for a dated note without a
    /// class (a lab that was moved, a make-up lecture).
    public var id: String
    public var courseID: CourseID
    public var date: LocalDate
    /// Start of the class; `nil` for a note without a class.
    public var start: LocalTime?
    /// Session kind as written in the vault (`Lecture`).
    public var kind: String
    /// 1-based number among the classes of the same kind in the semester (Lecture **9**); `nil`
    /// for a note without a class.
    public var ordinal: Int?
    /// `Lecture 9`.
    public var label: String
    /// The part of the title after the number (`Membrane transport`), `nil` when there is none yet.
    public var theme: String?
    public var room: String?
    /// The note of the class. When the class has no note file yet this is a placeholder made from
    /// the timetable (`isPlaceholder`), not stored anywhere until the user opens the card.
    public var note: NoteSummary
    /// The class comes from the timetable (`false`: a dated note without a class).
    public var fromSchedule: Bool
    /// The class starts at or after "now".
    public var isUpcoming: Bool

    /// "Not started": nothing written yet.
    public var isNotStarted: Bool { note.isPlaceholder }

    public init(id: String, courseID: CourseID, date: LocalDate, start: LocalTime?, kind: String, ordinal: Int?,
                label: String, theme: String?, room: String?, note: NoteSummary, fromSchedule: Bool, isUpcoming: Bool) {
        self.id = id; self.courseID = courseID; self.date = date; self.start = start; self.kind = kind
        self.ordinal = ordinal; self.label = label; self.theme = theme; self.room = room; self.note = note
        self.fromSchedule = fromSchedule; self.isUpcoming = isUpcoming
    }
}

/// Generates the cards of a course from its timetable (M4-08).
///
/// - **Classes:** every occurrence of every `Session` of the course in the semester (skipping break
///   weeks and days outside the term) up to `now.date + lookaheadDays`. Numbering counts classes of
///   the same kind (case-insensitive) from the start of the term, so it does not depend on the
///   lookahead.
/// - **Notes:** a class gets the note of the course that has the class's date and kind (or, for an
///   undated note, a title that starts with the label, `Lecture 9`). Every note is used once. A
///   class without a note is a "Not started" card whose note is a placeholder
///   (`NoteSummary.isPlaceholder`) titled by the label, with the id `<course>/<slug of label>` that
///   `NoteRepository.create` would give it.
/// - **Extra cards:** a dated class note (`lecture`, `lab`, `seminar`, `tutorial`) that no class
///   claimed and that is not after the horizon still gets a card (`fromSchedule == false`).
/// - **Order:** newest first (date, then start), as in the gallery.
/// - `includePastWithoutNote: false` leaves out "Not started" cards of days before today.
public enum CourseCardBuilder {
    /// Separator between label and theme in note titles (`Lecture 8 — Cell membrane`).
    public static let themeSeparator = " — "

    public static func cards(course: Course, semester: Semester, notes: [NoteSummary], now: LocalDateTime,
                             lookaheadDays: Int = 7, includePastWithoutNote: Bool = true) -> [CourseCard] {
        let horizon = now.date.adding(days: max(0, lookaheadDays))
        let occurrences = classes(of: course, in: semester)
        var counters: [String: Int] = [:]
        var numbered: [(SessionOccurrence, Int)] = []
        for occ in occurrences {
            let key = occ.session.kind.lowercased()
            counters[key, default: 0] += 1
            numbered.append((occ, counters[key]!))
        }

        var free = notes.filter { $0.courseID == course.id }
            .sorted { ($0.title.lowercased(), $0.id) < ($1.title.lowercased(), $1.id) }
        var cards: [CourseCard] = []
        for (occ, ordinal) in numbered where occ.date <= horizon {
            let label = "\(occ.session.kind) \(ordinal)"
            let kind = noteKind(of: occ.session.kind)
            let match = free.firstIndex { $0.date == occ.date && $0.kind == kind }
                ?? free.firstIndex { $0.date == nil && $0.kind == kind && isTitled($0.title, label: label) }
            let note = match.map { free.remove(at: $0) }
            if note == nil && !includePastWithoutNote && occ.date < now.date { continue }
            cards.append(card(for: occ, ordinal: ordinal, note: note, now: now))
        }
        for note in free where note.date.map({ $0 <= horizon }) == true && isClassKind(note.kind) {
            cards.append(extraCard(for: note, now: now))
        }
        let midnight = LocalTime.literal(0)
        return cards.sorted {
            ($0.date, $0.start ?? midnight, $0.id) > ($1.date, $1.start ?? midnight, $1.id)
        }
    }

    /// The card of one class. `note == nil` gives the "Not started" placeholder made from the
    /// timetable.
    public static func card(for occurrence: SessionOccurrence, ordinal: Int, note: NoteSummary?, now: LocalDateTime) -> CourseCard {
        let session = occurrence.session
        let label = "\(session.kind) \(ordinal)"
        let summary = note ?? placeholder(for: occurrence, label: label)
        return CourseCard(
            id: occurrence.id, courseID: session.courseID, date: occurrence.date, start: session.start,
            kind: session.kind, ordinal: ordinal, label: label, theme: theme(ofTitle: summary.title, label: label),
            room: session.room, note: summary, fromSchedule: true, isUpcoming: occurrence.start >= now)
    }

    // MARK: Internals

    /// Occurrences of the course's sessions inside the term, oldest first.
    static func classes(of course: Course, in semester: Semester) -> [SessionOccurrence] {
        var result: [SessionOccurrence] = []
        let firstMonday = semester.start.startOfWeek
        for week in 1...max(1, semester.weekCount) where !semester.breakWeeks.contains(week) {
            let monday = firstMonday.adding(days: (week - 1) * 7)
            for session in course.sessions {
                let date = monday.adding(days: session.day.isoNumber - 1)
                if date >= semester.start && date <= semester.end { result.append(SessionOccurrence(session: session, date: date)) }
            }
        }
        return result.sorted { ($0.date, $0.session.start, $0.session.id) < ($1.date, $1.session.start, $1.session.id) }
    }

    private static func placeholder(for occurrence: SessionOccurrence, label: String) -> NoteSummary {
        let session = occurrence.session
        return NoteSummary(
            id: ServiceRules.noteID(course: session.courseID, title: label), courseID: session.courseID, title: label,
            kind: noteKind(of: session.kind), date: occurrence.date,
            snippet: "Not started. Created from your timetable at \(session.start.string).", isPlaceholder: true)
    }

    private static func extraCard(for note: NoteSummary, now: LocalDateTime) -> CourseCard {
        let (label, theme) = split(note.title)
        return CourseCard(
            id: note.id, courseID: note.courseID ?? "", date: note.date ?? now.date, start: nil,
            kind: note.kind.rawValue.capitalized, ordinal: nil, label: label, theme: theme, room: nil, note: note,
            fromSchedule: false, isUpcoming: (note.date ?? now.date) >= now.date)
    }

    /// `Lecture 9 — Membrane transport` -> (`Lecture 9`, `Membrane transport`).
    private static func split(_ title: String) -> (label: String, theme: String?) {
        guard let r = title.range(of: themeSeparator) else { return (title, nil) }
        let theme = String(title[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (String(title[..<r.lowerBound]), theme.isEmpty ? nil : theme)
    }

    private static func theme(ofTitle title: String, label: String) -> String? {
        if title == label { return nil }
        if title.hasPrefix(label + themeSeparator) {
            let t = String(title.dropFirst(label.count + themeSeparator.count)).trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        return title
    }

    private static func isTitled(_ title: String, label: String) -> Bool {
        title == label || title.hasPrefix(label + themeSeparator)
    }

    private static func isClassKind(_ kind: NoteKind) -> Bool {
        switch kind { case .lecture, .lab, .seminar, .tutorial: true; case .study, .note: false }
    }

    /// The note kind that goes with a session kind (`Lab` -> `.lab`); anything else is `.note`.
    static func noteKind(of sessionKind: String) -> NoteKind {
        switch sessionKind.lowercased() {
        case "lecture": .lecture
        case "lab": .lab
        case "seminar": .seminar
        case "tutorial": .tutorial
        default: .note
        }
    }
}

extension CourseCardBuilder {
    /// The cards of a course from the services alone (`CourseCatalog`, `NoteRepository`, `Clock`).
    /// Unknown course: `.notFound`; a course whose semester is unknown: `.notFound`.
    public static func cards(courseID: CourseID, catalog: any CourseCatalog, notes: any NoteRepository,
                             clock: any Clock, lookaheadDays: Int = 7,
                             includePastWithoutNote: Bool = true) async throws -> [CourseCard] {
        let course = try await catalog.course(id: courseID)
        guard let semester = try await catalog.semesters().first(where: { $0.id == course.semester }) else {
            throw MarginError.notFound("No semester \(course.semester)")
        }
        return cards(course: course, semester: semester, notes: try await notes.notes(course: courseID),
                     now: clock.localNow, lookaheadDays: lookaheadDays, includePastWithoutNote: includePastWithoutNote)
    }
}
