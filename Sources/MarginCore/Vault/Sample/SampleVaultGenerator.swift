import Foundation

/// Writes the sample vault of a `FixtureWorld` (M5-09): the same data the UI shows on
/// `Fixtures.week5`, as real files in the format of `docs/plan/05-vault-spec.md` §1–§7.
///
/// Layout:
/// ```
/// <Vault>/
/// ├─ .margin/semesters.json          semester dates (the vault has no other place for them)
/// ├─ Fall 2026/<Course>/_course.md   metadata, sessions, exams, grading (§5)
/// ├─ Fall 2026/<Course>/<Note>.md    frontmatter (§2), body with `@date` tasks (§3) and wikilinks (§4)
/// ├─ Fall 2026/<Course>/_files/      images embedded by notes
/// ├─ Fall 2026/<Course>/_grades.md   grades (§7), where the fixtures have some
/// └─ _inbox/<date> <time> <text>.md  inbox items (§6)
/// ```
///
/// The files are plain markdown and the YAML subset Obsidian reads; the generator adds only the
/// documented extensions (`id:` in notes and `_course.md`, `^id` on tasks, `@` due tokens).
///
/// The generator never overwrites: it fails with `MarginError.conflict` when a file already exists,
/// so it cannot damage a real vault. Generate into an empty folder.
public enum SampleVaultGenerator {
    /// What `generate` wrote.
    public struct Report: Sendable, Hashable {
        /// Every file created, in write order.
        public var files: [VaultPath] = []
        public var courseCount = 0
        public var noteCount = 0
        public var inboxCount = 0
    }

    /// Creates the sample vault of `world` in `store`.
    @discardableResult
    public static func generate(into store: VaultStore, from world: FixtureWorld = Fixtures.week5) async throws -> Report {
        var report = Report()
        for file in files(for: world) {
            if await store.exists(file.path) {
                throw MarginError.conflict("Sample vault target already contains \(file.path)")
            }
            switch file.content {
            case .text(let text): try await store.create(file.path, content: text)
            case .data(let data): try await store.writeData(file.path, data: data)
            }
            report.files.append(file.path)
        }
        report.courseCount = world.courses.count
        report.noteCount = world.allNotes.count
        report.inboxCount = world.inbox.count
        return report
    }

    // MARK: - Files

    struct File {
        enum Content { case text(String), data(Data) }
        var path: VaultPath
        var content: Content
    }

    /// The whole vault as `(path, content)` pairs, in a stable order. Pure: no I/O.
    static func files(for world: FixtureWorld) -> [File] {
        var out: [File] = []
        func add(_ components: [String], _ text: String) { out.append(File(path: path(components), content: .text(text))) }

        add([".margin", "semesters.json"], semestersJSON(world.semester))
        let semesterFolder = world.semester.name
        var courseFolders: [CourseID: String] = [:]
        for course in world.courses {
            courseFolders[course.id] = VaultPath.filename(fromTitle: course.name)
        }

        for course in world.courses {
            let folder = [semesterFolder, courseFolders[course.id] ?? course.name]
            add(folder + ["_course.md"], courseFile(course))
            for note in world.allNotes where note.courseID == course.id {
                guard let body = world.markdownBody(of: note.id) else { continue }
                add(folder + [VaultPath.filename(fromTitle: note.title) + ".md"], noteFile(note, course: course, body: body))
                if note.imageCount > 0 {
                    for n in 1...note.imageCount {
                        out.append(File(path: path(folder + ["_files", FixtureWorld.imageName(for: note, number: n)]),
                                        content: .data(tinyPNG)))
                    }
                }
            }
            let grades = world.grades.filter { $0.courseID == course.id }
            if !grades.isEmpty { add(folder + ["_grades.md"], gradesFile(grades, course: course)) }
        }
        for item in world.inbox {
            let time = item.captured.time
            let name = "\(item.captured.date.iso) \(String(format: "%02d%02d", time.hour, time.minute)) \(item.text)"
            add(["_inbox", VaultPath.filename(fromTitle: name) + ".md"], inboxFile(item))
        }
        return out
    }

    private static func path(_ components: [String]) -> VaultPath {
        // Components come from fixture titles, already sanitised by `filename(fromTitle:)`.
        (try? VaultPath(components: components)) ?? VaultPath.fallback
    }

    // MARK: - Renderers

    static func semestersJSON(_ s: Semester) -> String {
        """
        [
          {
            "id": \(quote(s.id)),
            "name": \(quote(s.name)),
            "start": "\(s.start.iso)",
            "end": "\(s.end.iso)",
            "breakWeeks": [\(s.breakWeeks.map(String.init).joined(separator: ", "))]
          }
        ]

        """
    }

    static func courseFile(_ c: Course) -> String {
        var y: [String] = ["---", "id: \(scalar(c.id))", "name: \(scalar(c.name))", "code: \(scalar(c.code))"]
        if let v = c.professor { y.append("professor: \(scalar(v))") }
        if let v = c.room { y.append("room: \(scalar(v))") }
        if let v = c.faculty { y.append("faculty: \(scalar(v))") }
        y.append("icon: \(scalar(c.style.icon))")
        y.append("color: \(scalar(c.style.color))")
        if let v = c.credits { y.append("credits: \(v)") }
        if !c.sessions.isEmpty {
            y.append("sessions:")
            for s in c.sessions {
                var parts = ["day: \(s.day.rawValue)", "time: \"\(s.start.string)\"", "length: \(number(s.lengthHours))",
                             "kind: \(scalar(s.kind))"]
                if let room = s.room { parts.append("room: \(quote(room))") }
                y.append("  - {\(parts.joined(separator: ", "))}")
            }
        }
        if !c.exams.isEmpty {
            y.append("exams:")
            for e in c.exams {
                var parts = ["title: \(scalar(e.title))", "date: \(e.date.iso)"]
                if let t = e.time { parts.append("time: \"\(t.string)\"") }
                parts.append("weight: \(e.weightPercent)%")
                y.append("  - {\(parts.joined(separator: ", "))}")
            }
        }
        if !c.grading.isEmpty {
            y.append("grading:")
            for g in c.grading { y.append("  - {label: \(scalar(g.label)), weight: \(g.weightPercent)%}") }
        }
        y.append("---")
        return y.joined(separator: "\n") + "\n\n# \(c.name)\n\n\(c.code)" + (c.professor.map { " · \($0)" } ?? "") + "\n"
    }

    static func noteFile(_ n: NoteSummary, course: Course, body: String) -> String {
        var y = ["---", "id: \(scalar(n.id))"]
        if let d = n.date { y.append("date: \(d.iso)") }
        y.append("class: \"[[\(course.name)]]\"")
        y.append("type: \(n.kind.rawValue)")
        y.append("---")
        return y.joined(separator: "\n") + "\n" + body
    }

    static func inboxFile(_ i: InboxItem) -> String {
        """
        ---
        captured: \(i.captured.iso)
        source: \(i.source.rawValue)
        kind: \(i.kind.rawValue)
        ---
        \(i.text)

        """
    }

    static func gradesFile(_ grades: [Grade], course: Course) -> String {
        var y = ["---", "grades:"]
        for g in grades {
            var parts = ["item: \(scalar(g.item))"]
            if let v = g.group { parts.append("group: \(scalar(v))") }
            if let v = g.weightPercent { parts.append("weight: \(v)%") }
            if let v = g.score { parts.append("score: \(number(v))") }
            if let v = g.max { parts.append("max: \(number(v))") }
            if let v = g.date { parts.append("date: \(v.iso)") }
            y.append("  - {\(parts.joined(separator: ", "))}")
        }
        y.append("---")
        var table = ["", "# Grades — \(course.name)", "", "| Item | Group | Weight | Score | Date |", "| --- | --- | --- | --- | --- |"]
        for g in grades {
            let score = g.score.map { "\(number($0))/\(number(g.max ?? 100))" } ?? ""
            table.append("| \(g.item) | \(g.group ?? "") | \(g.weightPercent.map { "\($0)%" } ?? "") | \(score) | \(g.date?.iso ?? "") |")
        }
        return (y + table).joined(separator: "\n") + "\n"
    }

    // MARK: - YAML helpers

    /// A YAML scalar: plain when that is unambiguous, double-quoted otherwise.
    static func scalar(_ s: String) -> String {
        let plain = !s.isEmpty && s.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)) || " ._/-+".unicodeScalars.contains($0)) }
            && s.first.map { $0.isLetter } == true && s.last != " "
            && !["true", "false", "null", "yes", "no", "on", "off"].contains(s.lowercased())
        return plain ? s : quote(s)
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            default: out.unicodeScalars.append(u)
            }
        }
        return out + "\""
    }

    private static func number(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : "\(d)"
    }

    /// A valid 1×1 PNG (attachments must be real images for Obsidian to show them).
    static let tinyPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==") ?? Data()
}

extension VaultPath {
    /// Never used for valid input; keeps the generator free of `try!`.
    fileprivate static let fallback = VaultPath(unchecked: ["Untitled.md"])
}
