import Foundation

/// The pure rules of capture and inbox writes shared by the fixture and the vault services, so the
/// two cannot drift (contract §5). Spec: `05-vault-spec.md` §6 (inbox files) and §3 (task lines).
///
/// Where a capture ends up:
///
/// - **No course:** a new file `_inbox/<yyyy-MM-dd> <HHmm> <text>.md` with the frontmatter of §6
///   (`captured`, `source: quick-capture`, `kind`) and the text as body. A due date and tags of
///   the draft are written into the body as `@yyyy-MM-dd` and `#tag`, so triage can restore them.
/// - **Course, task:** one line `- [ ] <text> #tag @yyyy-MM-dd ^t-xxxx` appended to
///   `<semester>/<course>/Tasks.md`, the course's task note. The note is created when missing
///   (frontmatter `id`, `class`, `type: note`, heading `# Tasks`).
/// - **Course, note/link/image:** a new note in the course folder, titled after the first line
///   of the text, with frontmatter `id`, `date`, `class`, `type: note`, `tags`.
/// - **`attachTo`:** wins over everything else: a task line or a paragraph is appended to that note.
enum CaptureRules {
    /// The name of the task note every course can have.
    static let tasksNoteTitle = "Tasks"
    /// Longest text used in a new inbox file name (characters).
    static let inboxNameTextLimit = 80
    /// Longest title derived from capture text (characters).
    static let titleLimit = 60

    // MARK: Text

    /// The trimmed text; `.invalid` when nothing is left.
    static func validatedText(_ text: String) throws -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw MarginError.invalid("A capture needs text") }
        return t
    }

    /// Newlines and tabs collapse to single spaces (a task is one line).
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isNewline || $0 == "\t" }).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func hashtags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in tags {
            let t = raw.trimmingCharacters(in: CharacterSet(charactersIn: "# \t\n"))
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
            if !t.isEmpty, seen.insert(t.lowercased()).inserted { out.append(t) }
        }
        return out
    }

    /// The title of a note made from `text`: its first line, cut at a word boundary.
    static func title(from text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        var t = first.trimmingCharacters(in: .whitespaces)
        if t.count > titleLimit {
            let cut = String(t.prefix(titleLimit))
            if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > titleLimit / 2 {
                t = String(cut[..<space])
            } else {
                t = cut
            }
            t = t.trimmingCharacters(in: .whitespaces)
        }
        return t.isEmpty ? "Untitled" : t
    }

    // MARK: Task lines

    /// `- [ ] text #tag @2026-10-02 ^t-4f2a`
    static func taskLine(text: String, tags: [String], due: LocalDate?, id: String) -> String {
        var line = "- [ ] " + oneLine(text)
        for t in hashtags(tags) { line += " #" + t }
        if let due { line += " @" + due.iso }
        return line + " ^" + id
    }

    /// The text of an uncategorised capture as written into an inbox file body.
    static func inboxBody(_ draft: CaptureDraft, text: String) -> String {
        guard draft.kind == .task else { return text }
        var body = text
        for t in hashtags(draft.tags) { body += " #" + t }
        if let due = draft.due { body += " @" + due.iso }
        return body
    }

    /// Appends `line` (no line break) to `content`, keeping a CRLF file CRLF.
    static func append(line: String, to content: String) -> String {
        let eol = content.contains("\r\n") ? "\r\n" : "\n"
        var out = content
        if !out.isEmpty, !out.hasSuffix("\n") { out += eol }
        return out + line + eol
    }

    /// Appends a paragraph (a blank line first) to `content`.
    static func append(paragraph: String, to content: String) -> String {
        let eol = content.contains("\r\n") ? "\r\n" : "\n"
        var out = content
        if !out.isEmpty, !out.hasSuffix("\n") { out += eol }
        if !out.isEmpty, !out.hasSuffix(eol + eol), out != eol { out += eol }
        return out + paragraph + eol
    }

    // MARK: Inbox files

    static func hhmm(_ t: LocalTime) -> String { String(format: "%02d%02d", t.hour, t.minute) }

    /// File name stem of an inbox item: `2026-09-28 0912 Email Dr. Okafor about lab partner`.
    static func inboxStem(captured: LocalDateTime, text: String) -> String {
        let first = oneLine(text)
        let short = first.count > inboxNameTextLimit ? String(first.prefix(inboxNameTextLimit)) : first
        return VaultPath.filename(fromTitle: "\(captured.date.iso) \(hhmm(captured.time)) \(short)")
    }

    /// The stem with a counter (` 2`, ` 3`, …) until `taken` says it is free.
    static func freeStem(_ stem: String, taken: (String) -> Bool) -> String {
        if !taken(stem) { return stem }
        var n = 2
        while taken("\(stem) \(n)") { n += 1 }
        return "\(stem) \(n)"
    }

    static let inboxFolder = "_inbox"

    /// Spec §6 file content.
    static func inboxFile(_ item: InboxItem) -> String { SampleVaultGenerator.inboxFile(item) }

    /// Reads an inbox file. A hand-made file without frontmatter is accepted: it becomes a `note`
    /// captured at the date and time in its name, else at `fallback`. `nil` when the body is empty.
    static func parseInboxFile(stem: String, content: String, fallback: LocalDateTime) -> InboxItem? {
        let (fm, body) = Frontmatter.parse(content)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let captured = fm?.string(for: "captured").flatMap { LocalDateTime(iso: $0) } ?? capturedTime(inStem: stem) ?? fallback
        let kind = fm?.string(for: "kind").flatMap { InboxKind(rawValue: $0) } ?? .note
        let source = fm?.string(for: "source").flatMap { InboxSource(rawValue: $0) } ?? .share
        return InboxItem(id: stem, text: text, kind: kind, source: source, captured: captured)
    }

    /// `2026-09-28 0912 …` in a file name.
    static func capturedTime(inStem stem: String) -> LocalDateTime? {
        let parts = stem.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, let date = LocalDate(iso: String(parts[0])), parts[1].count == 4,
              let h = Int(parts[1].prefix(2)), let m = Int(parts[1].suffix(2)), let time = LocalTime(hour: h, minute: m)
        else { return nil }
        return LocalDateTime(date: date, time: time)
    }

    /// Newest first, then by id.
    static func sortInbox(_ items: [InboxItem]) -> [InboxItem] {
        items.sorted { $0.captured != $1.captured ? $0.captured > $1.captured : $0.id < $1.id }
    }

    /// What triage does with an inbox item's text as a task: text without the `@due` token, and the
    /// due day it named (`when` overrides it).
    static func taskParts(ofInboxText text: String, when: LocalDate?, clock: any Clock) -> (text: String, due: LocalDate?) {
        let line = oneLine(text)
        let parsed = TaskExtractor(clock: clock).extract(from: "- [ ] " + line).first
        let clean = (parsed?.text.isEmpty == false ? parsed?.text : nil) ?? line
        return (clean, when ?? parsed?.due)
    }

    // MARK: Notes

    /// Frontmatter and body of a note made by a capture or a triage (vault form; the fixture keeps
    /// the body only).
    static func noteBody(title: String, text: String) -> String {
        let oneLineTitle = oneLine(text)
        return oneLineTitle == title && !text.contains("\n") ? "# \(title)\n" : "# \(title)\n\n\(text)\n"
    }

    static func noteFile(id: String, courseName: String, date: LocalDate, tags: [String], title: String, text: String) -> String {
        var y = ["---", "id: \(SampleVaultGenerator.scalar(id))", "date: \(date.iso)",
                 "class: \"[[\(courseName)]]\"", "type: note"]
        let tags = hashtags(tags)
        if !tags.isEmpty { y.append("tags:"); for t in tags { y.append("  - \(SampleVaultGenerator.scalar(t))") } }
        y.append("---")
        return y.joined(separator: "\n") + "\n" + noteBody(title: title, text: text)
    }

    /// The content of a fresh `Tasks.md`.
    static func tasksNoteFile(id: String, courseName: String, line: String) -> String {
        """
        ---
        id: \(SampleVaultGenerator.scalar(id))
        class: "[[\(courseName)]]"
        type: note
        ---
        # \(tasksNoteTitle)

        \(line)

        """
    }
}
