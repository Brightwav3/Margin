// Markdown bodies of the fixture notes (M5-09).
//
// The typed `Fixtures.week5` world has no note text. To let the sample vault generator, the
// `Fixture…` services and the conformance tests agree on it, the body of every note is derived
// here from the typed data: heading, snippet, tasks (from `dueItems` and a small table for the
// notes that count tasks), wikilinks (from the graph edges) and filler text up to the mockup's
// word count. `FixtureWorld.markdownBody(of:)` is the single source; the generator and
// `FixtureNoteRepository` both use it, so a note reads the same from either implementation.

/// One task line of a fixture note.
struct FixtureTaskLine: Sendable, Hashable {
    var id: String
    var text: String
    var done: Bool
    var due: LocalDate?
}

extension FixtureWorld {
    /// One `Assignments` note per course that has due tasks. It holds the tasks of `dueItems`
    /// (their `source.noteID` is `<course>/assignments`). Exams are not tasks: they come from
    /// the course.
    var assignmentNotes: [NoteSummary] {
        courses.compactMap { course in
            let lines = taskLines(ofNote: "\(course.id)/assignments")
            guard !lines.isEmpty else { return nil }
            return NoteSummary(
                id: "\(course.id)/assignments", courseID: course.id, title: "Assignments", kind: .note,
                snippet: "Graded work and deadlines for \(course.name).",
                openTasks: lines.filter { !$0.done }.count, totalTasks: lines.count)
        }
    }

    /// `notes` plus the assignment notes: everything the sample vault contains as a note.
    var allNotes: [NoteSummary] { notes + assignmentNotes }

    /// Tasks written into a note's body, in line order.
    func taskLines(ofNote id: NoteID) -> [FixtureTaskLine] {
        if id.hasSuffix("/assignments") {
            let course = String(id.dropLast("/assignments".count))
            return dueItems.filter { $0.kind == .task && $0.source.courseID == course }.map {
                FixtureTaskLine(id: $0.id, text: $0.text, done: $0.done, due: $0.due)
            }
        }
        guard let summary = notes.first(where: { $0.id == id }), summary.totalTasks > 0 else { return [] }
        // The mockup only counts these tasks (open / total); the texts are invented, the first two
        // are the examples from the vault spec (05 §3).
        let texts = ["Ask about the osmosis question in office hours", "Redraw the bilayer diagram from memory",
                     "Label the organelle diagram", "Summarise the key terms", "Compare with the lecture slides"]
        let slug = String(id.split(separator: "/").last ?? "")
        let doneCount = summary.totalTasks - summary.openTasks
        return (0..<summary.totalTasks).map { n in
            // Done tasks come first so the open ones keep the spec's example texts.
            FixtureTaskLine(id: "task-\(slug)-\(n + 1)", text: texts[(n + (id.hasSuffix("lecture-7") ? 2 : 0)) % texts.count],
                            done: n < doneCount, due: nil)
        }
    }

    /// The markdown body (no frontmatter) of a fixture note; `nil` for an unknown id.
    ///
    /// Notes with a mockup word count are padded with filler text to exactly that many
    /// whitespace-separated words, so the index reports the numbers of the mockup.
    func markdownBody(of id: NoteID) -> String? {
        guard let summary = allNotes.first(where: { $0.id == id }) else { return nil }
        var text = "# \(summary.title)\n"
        if !summary.snippet.isEmpty { text += "\n\(summary.snippet)\n" }

        if summary.imageCount > 0 {
            text += "\n"
            for n in 1...summary.imageCount { text += "![[\(Self.imageName(for: summary, number: n))]]\n" }
        }
        let tasks = taskLines(ofNote: id)
        if !tasks.isEmpty {
            text += "\n## Tasks\n\n"
            for t in tasks {
                text += "- [\(t.done ? "x" : " ")] \(t.text)\(t.due.map { " @\($0.iso)" } ?? "") ^\(t.id)\n"
            }
        }
        let related = relatedLinkTargets(of: summary)
        if !related.isEmpty {
            text += "\n## Related\n\n"
            for target in related { text += "- [[\(target)]]\n" }
        }
        if summary.wordCount > 0 {
            let padded = text + "\n## Notes\n\n"
            let missing = summary.wordCount - NoteIndex.wordCount(padded)
            if missing > 0 { text = padded + Self.filler(words: missing) + "\n" }
        }
        return text
    }

    /// File name of the n-th image of a note (`lab-2-1.png`).
    static func imageName(for note: NoteSummary, number: Int) -> String {
        "\(note.id.split(separator: "/").last ?? "image")-\(number).png"
    }

    /// Link targets of a note from the graph: edges that start at the note's node and end at a
    /// note node. A target that has no note yet is written as it is labelled in the graph, an
    /// intentional "not created yet" link (vault spec §4).
    func relatedLinkTargets(of summary: NoteSummary) -> [String] {
        guard let node = graph.nodes.first(where: { $0.kind == .note && Self.matches($0.label, summary.title) }) else {
            return []
        }
        var targets: [String] = []
        for edge in graph.edges where edge.source == node.id {
            guard let other = graph.nodes.first(where: { $0.id == edge.target }), other.kind == .note else { continue }
            let title = allNotes.first { Self.matches(other.label, $0.title) }?.title ?? other.label
            if title != summary.title, !targets.contains(title) { targets.append(title) }
        }
        return targets
    }

    /// Titles of link targets that no fixture note has (the "not created yet" links).
    var notCreatedLinkTargets: Set<String> {
        var result = Set<String>()
        for note in allNotes {
            for target in relatedLinkTargets(of: note) where !allNotes.contains(where: { $0.title == target }) {
                result.insert(target)
            }
        }
        return result
    }

    /// Graph labels are shorter than note titles ("Membrane transport" / "Membrane transport
    /// summary", "1848 revolutions" / "The 1848 revolutions").
    static func matches(_ label: String, _ title: String) -> Bool {
        func norm(_ s: String) -> String {
            var t = s.lowercased()
            if t.hasPrefix("the ") { t.removeFirst(4) }
            if t.hasSuffix(" summary") { t.removeLast(8) }
            return t
        }
        return norm(label) == norm(title)
    }

    private static let fillerSentences = [
        "The membrane separates the cell from its surroundings and controls what passes through.",
        "Small nonpolar molecules diffuse across the bilayer while ions need channels or pumps.",
        "Remember to compare the two models and note where the evidence differs.",
        "Worked examples from the textbook are a good way to check the definitions.",
        "Bring questions about this topic to the next tutorial and to office hours.",
        "Each section builds on the previous one, so review the earlier notes first.",
    ]

    /// Exactly `words` whitespace-separated words of deterministic filler text, in paragraphs of
    /// four sentences (only the last sentence may be cut short).
    static func filler(words: Int) -> String {
        var text = ""
        var count = 0
        var sentence = 0
        while count < words {
            let w = fillerSentences[sentence % fillerSentences.count].split(separator: " ").map(String.init)
            let take = Array(w.prefix(words - count))
            var chunk = take.joined(separator: " ")
            if take.count < w.count, let last = chunk.last, !".!?".contains(last) { chunk += "." }
            if sentence > 0 { text += sentence % 4 == 0 ? "\n\n" : " " }
            text += chunk
            count += take.count
            sentence += 1
        }
        return text
    }
}
