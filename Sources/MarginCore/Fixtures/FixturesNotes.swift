// Notes, inbox and grades of `Fixtures.week5` (M2-04). Source: `bioGallery`, `noteList`, `refNotes`,
// `C[].lastNote`, `inbox` in Margin.dc.html and the Grades screen (1e) in Margin-Screens.dc.html.

extension Fixtures {
    private static func note(
        _ slug: String, course: CourseID, _ title: String, kind: NoteKind, date: LocalDate? = nil,
        _ snippet: String, words: Int = 0, open: Int = 0, total: Int = 0, images: Int = 0,
        placeholder: Bool = false, modified: LocalDateTime? = nil
    ) -> NoteSummary {
        NoteSummary(
            id: "\(course)/\(slug)", courseID: course, title: title, kind: kind, date: date,
            snippet: snippet, wordCount: words, openTasks: open, totalTasks: total, imageCount: images,
            isPlaceholder: placeholder, modified: modified)
    }

    /// `modified` for notes the mockup dates only as "N days ago". The time of day is invented (12:00).
    private static func ago(_ days: Int) -> LocalDateTime {
        LocalDateTime(date: today.adding(days: -days), time: .literal(12))
    }

    // The first six entries are the Cell Biology gallery cards, in mockup order. In the mockup Lecture 7
    // shows "Done" without a count: `totalTasks: 1` is an assumption. Lab 2 is dated Mon 21 Sep in the
    // gallery but Mon 14 Sep in the lecture list; the gallery wins.
    static let notes: [NoteSummary] = [
        note("lecture-9", course: "bio", "Lecture 9 — Membrane transport", kind: .lecture, date: .literal(2026, 9, 29),
             "Not started. Created from your timetable at 10:00; readings: ch. 6.", placeholder: true),
        note("lecture-8", course: "bio", "Lecture 8 — Cell membrane", kind: .lecture, date: .literal(2026, 9, 24),
             "Phospholipid bilayer and the fluid mosaic model. Cholesterol keeps it fluid.",
             words: 412, open: 2, total: 2,
             modified: LocalDateTime(date: today, time: .literal(9))),
        note("lecture-7", course: "bio", "Lecture 7 — Organelles", kind: .lecture, date: .literal(2026, 9, 22),
             "Nucleus, mitochondria, ER, Golgi. Structure and function of each.", words: 680, total: 1),
        note("lab-2", course: "bio", "Lab 2 — Microscopy", kind: .lab, date: .literal(2026, 9, 21),
             "Onion epidermis and cheek cells at 400×. Sketches attached.", images: 3),
        note("lecture-6", course: "bio", "Lecture 6 — Prokaryotes and eukaryotes", kind: .lecture, date: .literal(2026, 9, 17),
             "Key differences: nucleus, organelles, size, ribosome type.", words: 520),
        note("lecture-5", course: "bio", "Lecture 5 — Proteins and enzymes", kind: .lecture, date: .literal(2026, 9, 15),
             "Primary to quaternary structure. Lock and key vs induced fit.", words: 590),
        // Other Cell Biology notes (`refNotes`, `noteList`).
        note("membrane-transport-summary", course: "bio", "Membrane transport summary", kind: .study,
             "Passive vs active transport, with examples.", modified: ago(1)),
        note("glossary", course: "bio", "Glossary", kind: .study, "Terms to know for the midterm.", modified: ago(3)),
        note("midterm-formula-sheet", course: "bio", "Midterm formula sheet", kind: .study, "", modified: ago(7)),
        // One recent note per other course (`C[].lastNote`, `snippet`, `edited`).
        note("stereochemistry", course: "chem", "Stereochemistry", kind: .lecture,
             "Chiral centres and R/S naming…", modified: ago(1)),
        note("determinants", course: "math", "Determinants", kind: .lecture,
             "Row operations and cofactor expansion…", modified: ago(2)),
        note("the-1848-revolutions", course: "hist", "The 1848 revolutions", kind: .lecture,
             "Causes across France, Prussia and Austria…", modified: ago(3)),
        note("is-lm-model", course: "econ", "IS–LM model", kind: .lecture,
             "Equilibrium in goods and money markets…", modified: ago(4)),
        note("the-chinese-room", course: "phil", "The Chinese Room", kind: .seminar,
             "Searle's argument against strong AI…", modified: ago(5)),
    ]

    // Capture times: only "9:12" and "8:40" (today) are exact; "Yesterday" and "Sat" carry an invented
    // time. Sources are invented as well (the mockup has none).
    static let inbox: [InboxItem] = [
        InboxItem(id: "inbox-1", text: "Email Dr. Okafor about lab partner", kind: .task, source: .phone,
                  captured: LocalDateTime(date: today, time: .literal(9, 12))),
        InboxItem(id: "inbox-2", text: "Idea: compare 1848 to Arab Spring for essay", kind: .note, source: .quickCapture,
                  captured: LocalDateTime(date: today, time: .literal(8, 40))),
        InboxItem(id: "inbox-3", text: "Khan Academy — eigenvectors intro", kind: .link, source: .share,
                  captured: LocalDateTime(date: today.adding(days: -1), time: .literal(18, 30))),
        InboxItem(id: "inbox-4", text: "Whiteboard photo, ECON tutorial", kind: .image, source: .phone,
                  captured: LocalDateTime(date: today.adding(days: -1), time: .literal(17, 5))),
        InboxItem(id: "inbox-5", text: "Print lab safety form", kind: .task, source: .quickCapture,
                  captured: LocalDateTime(date: today.adding(days: -2), time: .literal(11, 0))),
    ]

    // Grades screen (1e), Cell Biology: item weights (5/5/15/5/30/40, 25% graded) differ from the
    // `grading` parts of the course (20/25/25/30); both are transcribed as shown. "Lab 1 report 88%" is
    // stored as 88/100; "Dec" is resolved to the final exam on 11 Dec (Margin.dc.html `gradeParts`).
    static let grades: [Grade] = [
        Grade(id: "grade-bio-ps1", courseID: "bio", item: "Problem set 1", group: "Problem sets", weightPercent: 5, score: 19, max: 20),
        Grade(id: "grade-bio-ps2", courseID: "bio", item: "Problem set 2", group: "Problem sets", weightPercent: 5, score: 18, max: 20),
        Grade(id: "grade-bio-lab1", courseID: "bio", item: "Lab 1 report", group: "Lab reports", weightPercent: 15, score: 88, max: 100),
        Grade(id: "grade-bio-ps3", courseID: "bio", item: "Problem set 3", group: "Problem sets", weightPercent: 5, date: .literal(2026, 10, 2)),
        Grade(id: "grade-bio-midterm", courseID: "bio", item: "Midterm", group: "Midterm", weightPercent: 30, date: .literal(2026, 10, 1)),
        Grade(id: "grade-bio-final", courseID: "bio", item: "Final exam", group: "Final exam", weightPercent: 40, date: .literal(2026, 12, 11)),
    ]

    /// `C[].grade` / `pct` (semester average in the mockup: A−, 89.6%).
    static let gradeSummaries: [GradeSummary] = [
        GradeSummary(courseID: "bio", letter: "A−", percent: 91),
        GradeSummary(courseID: "chem", letter: "B+", percent: 87),
        GradeSummary(courseID: "math", letter: "A", percent: 94),
        GradeSummary(courseID: "hist", letter: "B", percent: 84),
        GradeSummary(courseID: "econ", letter: "A−", percent: 90),
        GradeSummary(courseID: "phil", letter: "B+", percent: 88),
    ]
}

extension FixtureWorld {
    /// The note with a short markdown body derived from its summary (fixture only).
    public func note(_ id: NoteID) -> Note? {
        guard let s = notes.first(where: { $0.id == id }) else { return nil }
        return Note(summary: s, text: "# \(s.title)\n\n\(s.snippet)\n", version: "1")
    }
}
