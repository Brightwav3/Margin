import Foundation

/// The lecture a capture "for the lecture" belongs to, and the lecture note of it, if any.
public struct LectureTarget: Codable, Sendable, Hashable {
    /// Day of the lecture.
    public var date: LocalDate
    /// Start time from the schedule; `nil` when the target comes from an existing note only.
    public var start: LocalTime?
    /// The lecture note of that day. `nil`: there is none yet, create one titled `suggestedTitle`.
    public var noteID: NoteID?
    /// `Lecture N` with N one above the highest `Lecture <n>` number among the course's notes
    /// (1 when there is none). For creating the missing note.
    public var suggestedTitle: String
    /// The lecture has not begun yet.
    public var isUpcoming: Bool

    public init(date: LocalDate, start: LocalTime? = nil, noteID: NoteID? = nil, suggestedTitle: String,
                isUpcoming: Bool = false) {
        self.date = date; self.start = start; self.noteID = noteID
        self.suggestedTitle = suggestedTitle; self.isUpcoming = isUpcoming
    }
}

/// Finds the nearest lecture of a course (M8-09) and inserts a line into its note.
///
/// **Nearest lecture.** Candidates are the course's sessions of kind `Lecture` (case-insensitive)
/// on the days within a week of today (inside the semester and outside its break weeks, when one is given). A lecture's
/// distance from now is 0 while it is on (start and end inclusive), else the minutes to its start
/// (upcoming) or since its end (past). The smallest distance wins; a tie goes to the lecture that
/// is already over, then to the earlier start. A lecture more than 7 days away is not a candidate.
/// Examples for a Tue/Thu 10:00-11:30 course: Tue 09:59 → Tue (upcoming); Tue 14:00 → Tue;
/// Wed 10:45 → Tue (tie), Wed 10:46 → Thu; Saturday → Thu; Sunday noon → Tue. Times are local
/// wall-clock times from the `Clock`; a day-long DST shift does not change which lecture is nearer.
///
/// **No lecture in reach** (no lecture sessions, the semester is over or not yet begun, a break week):
/// the lecture note dated nearest to today (a tie goes to the past), or `nil`.
///
/// **The note.** A lecture note (`kind == .lecture`, dated) of the course whose date is the day of
/// the lecture; with several, the one with the smaller id.
///
/// **Cancelled and moved classes.** `resolve(course:notes:occurrences:)` takes the concrete classes
/// (`CourseCatalog.sessions(week:)`, overrides applied): a cancelled lecture is not a candidate and
/// a moved one counts on its new day and time. The weekly variant without occurrences reads the
/// schedule only.
public struct LectureNoteResolver: Sendable {
    /// How far (in days) a scheduled lecture may be from now to be picked.
    public static let horizonDays = 7

    public let clock: any Clock

    public init(clock: any Clock) { self.clock = clock }

    /// The nearest lecture of `course` now, or `nil` when the course has neither a lecture within
    /// reach nor a dated lecture note.
    public func resolve(course: Course, notes: [NoteSummary], semester: Semester? = nil) -> LectureTarget? {
        let today = clock.today
        var classes: [(date: LocalDate, session: Session)] = []
        for offset in -Self.horizonDays...Self.horizonDays {
            let date = today.adding(days: offset)
            if let semester, !Self.isTeaching(date, in: semester) { continue }
            for s in course.sessions where s.day == date.weekday { classes.append((date, s)) }
        }
        return resolve(course: course, notes: notes, classes: classes)
    }

    /// The nearest lecture among concrete classes: cancelled ones are skipped, moved ones count on
    /// their new day (`SessionOccurrence.date`) and time.
    public func resolve(course: Course, notes: [NoteSummary], occurrences: [SessionOccurrence]) -> LectureTarget? {
        let classes = occurrences.filter { $0.session.courseID == course.id && !$0.isCancelled }.map { ($0.date, $0.session) }
        return resolve(course: course, notes: notes, classes: classes)
    }

    private func resolve(course: Course, notes: [NoteSummary], classes: [(date: LocalDate, session: Session)]) -> LectureTarget? {
        let lectureNotes = notes.filter { $0.courseID == course.id && $0.kind == .lecture && $0.date != nil }
        let title = Self.suggestedTitle(courseNotes: notes.filter { $0.courseID == course.id })
        let today = clock.today
        let now = Self.minutes(clock.localNow.date, clock.localNow.time)

        struct Candidate { var date: LocalDate; var start: LocalTime; var distance: Int; var upcoming: Bool; var startMinutes: Int }
        var best: Candidate?
        for (date, s) in classes where s.kind.caseInsensitiveCompare("Lecture") == .orderedSame {
            let start = Self.minutes(date, s.start)
            let end = start + s.lengthMinutes
            let distance = now < start ? start - now : (now > end ? now - end : 0)
            guard distance <= Self.horizonDays * 1440 else { continue }
            let c = Candidate(date: date, start: s.start, distance: distance, upcoming: now < start, startMinutes: start)
            if let b = best {
                let cKey = (c.distance, c.upcoming ? 1 : 0, c.startMinutes)
                let bKey = (b.distance, b.upcoming ? 1 : 0, b.startMinutes)
                if cKey < bKey { best = c }
            } else {
                best = c
            }
        }
        if let best {
            let note = lectureNotes.filter { $0.date == best.date }.min { $0.id < $1.id }
            return LectureTarget(date: best.date, start: best.start, noteID: note?.id, suggestedTitle: title, isUpcoming: best.upcoming)
        }
        // No lecture in reach: the lecture note dated nearest to today, the past first.
        let nearest = lectureNotes.min {
            let (a, b) = (abs(today.days(to: $0.date ?? today)), abs(today.days(to: $1.date ?? today)))
            if a != b { return a < b }
            let (pa, pb) = (($0.date ?? today) <= today ? 0 : 1, ($1.date ?? today) <= today ? 0 : 1)
            return pa != pb ? pa < pb : $0.id < $1.id
        }
        guard let nearest, let date = nearest.date else { return nil }
        return LectureTarget(date: date, start: nil, noteID: nearest.id, suggestedTitle: title, isUpcoming: date > today)
    }

    /// `Lecture N`, N one above the highest `Lecture <n>` at the start of a note title.
    static func suggestedTitle(courseNotes: [NoteSummary]) -> String {
        var highest = 0
        for n in courseNotes {
            let lower = n.title.lowercased()
            guard lower.hasPrefix("lecture ") else { continue }
            let digits = lower.dropFirst("lecture ".count).prefix { $0.isASCII && $0.isNumber }
            if let v = Int(digits), v > highest { highest = v }
        }
        return "Lecture \(highest + 1)"
    }

    /// Inside the semester and not in one of its break weeks.
    private static func isTeaching(_ date: LocalDate, in semester: Semester) -> Bool {
        guard date >= semester.start, date <= semester.end else { return false }
        return !semester.breakWeeks.contains(semester.week(of: date) ?? -1)
    }

    private static func minutes(_ date: LocalDate, _ time: LocalTime) -> Int {
        date.daysSinceEpoch * 1440 + time.minutesSinceMidnight
    }

    // MARK: Inserting

    /// Appends `line` to the end of the note file `path`, atomically: the file is read, the line
    /// added and the result written only if the file is still the version that was read. A change
    /// made in between (another program, another insert) makes the step start again, up to 12 times,
    /// then the call throws `MarginError.conflict`. A CRLF file gets a CRLF line break. The
    /// frontmatter and all other bytes stay as they are.
    ///
    /// - Returns: the file change, or `.invalid` for an empty `line`, `.notFound` for a missing file.
    @discardableResult
    public static func insertLine(_ line: String, into path: VaultPath, store: VaultStore) async throws -> ChangeSet.Entry {
        let text = line.trimmingCharacters(in: .newlines)
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw MarginError.invalid("There is no line to insert") }
        var attempt = 0
        while true {
            attempt += 1
            let (content, version) = try await store.read(path)
            let updated = CaptureRules.append(line: text, to: content)
            do {
                let after = try await store.write(path, content: updated, expectedVersion: version)
                return ChangeSet.Entry(path: path.rawValue, kind: .modified, beforeHash: version.hex, afterHash: after.hex)
            } catch let e as MarginError {
                if e.code == "conflict", attempt < 12 { continue }
                throw e
            }
        }
    }
}
