import Foundation

/// In-memory index over all notes of a vault (M5-08).
///
/// Built from a `NoteContentSource` (or raw `(path, content)` pairs) and kept current with
/// `update`, `remove`, `rename` and `apply(_:)` (the `FileWatcher` output). It never touches the
/// disk itself. Wikilinks are stored unresolved and resolved at query time through a name index,
/// so incremental changes never leave stale backlinks.
///
/// Budgets (`04-engineering-rules.md`): 1000 notes build < 1 s, reindex of one file < 30 ms.
public actor NoteIndex {
    private let clock: any Clock
    private let extractor: TaskExtractor
    private let scanner = MarkdownScanner()
    private let wikilinks = WikilinkExtractor()
    private var source: (any NoteContentSource)?

    private var byPath: [String: NoteRecord] = [:]
    /// Note id -> path. Duplicate ids: the lexicographically smallest path wins.
    private var idToPath: [NoteID: String] = [:]
    /// Task id -> paths of the notes that contain it (one entry per occurrence).
    private var taskPaths: [String: [String]] = [:]
    /// Normalised file name -> paths.
    private var pathsByName: [String: Set<String>] = [:]
    /// Normalised link target file name -> paths of notes that contain such a link.
    private var linkers: [String: Set<String>] = [:]

    public init(clock: any Clock = SystemClock(), source: (any NoteContentSource)? = nil) {
        self.clock = clock
        self.extractor = TaskExtractor(clock: clock)
        self.source = source
    }

    // MARK: Build

    /// Replaces the index with the notes of `source` and keeps it for later `update`/`apply`.
    /// Unreadable files are skipped and returned as errors.
    @discardableResult
    public func build(from source: any NoteContentSource) async throws -> [String: MarginError] {
        self.source = source
        let paths = try await source.listMarkdown()
        var entries: [(path: String, content: String)] = []
        entries.reserveCapacity(paths.count)
        var failures: [String: MarginError] = [:]
        for p in paths {
            do { entries.append((p, try await source.read(p))) }
            catch { failures[p] = (error as? MarginError) ?? .io("\(error)") }
        }
        build(entries: entries)
        return failures
    }

    /// Replaces the index with the given notes.
    public func build(entries: [(path: String, content: String)]) {
        byPath = [:]; idToPath = [:]; taskPaths = [:]; pathsByName = [:]; linkers = [:]
        byPath.reserveCapacity(entries.count)
        for e in entries where Self.isMarkdown(e.path) {
            let record = makeRecord(path: e.path, text: e.content)
            insert(record)
        }
    }

    // MARK: Incremental changes

    /// Indexes `text` for `path`. Returns `false` (and does nothing) when the content hash is
    /// unchanged.
    @discardableResult
    public func update(path: String, content text: String) -> Bool {
        guard Self.isMarkdown(path) else { return false }
        if let old = byPath[path], old.contentHash == Self.hash(text) { return false }
        if let old = byPath[path] { detach(old) }
        insert(makeRecord(path: path, text: text))
        return true
    }

    /// Re-reads `path` from the source. A missing file removes the note.
    @discardableResult
    public func update(path: String) async throws -> Bool {
        guard let source else { throw MarginError.invalid("NoteIndex has no content source") }
        do {
            return update(path: path, content: try await source.read(path))
        } catch MarginError.notFound {
            return remove(path: path)
        }
    }

    @discardableResult
    public func remove(path: String) -> Bool {
        guard let old = byPath[path] else { return false }
        detach(old)
        return true
    }

    /// Moves a note to a new path (content unchanged). Course and name are re-derived; a note
    /// with a stable `id:` keeps its id and its tasks their `^id`, only a placeholder id follows the path. Returns `false` when `from` is unknown.
    @discardableResult
    public func rename(from: String, to: String) -> Bool {
        guard let old = byPath[from], Self.isMarkdown(to), from != to else { return false }
        detach(old)
        if let clash = byPath[to] { detach(clash) }
        insert(makeRecord(path: to, text: old.text))
        return true
    }

    /// Applies watcher output: created/modified re-read the file, deleted removes it.
    /// Non-markdown paths are ignored. Returns the paths whose read failed (other than missing).
    @discardableResult
    public func apply(_ changes: [FileChange]) async -> [String: MarginError] {
        var failures: [String: MarginError] = [:]
        for change in changes where Self.isMarkdown(change.path) {
            switch change.kind {
            case .deleted:
                remove(path: change.path)
            case .created, .modified:
                do { try await update(path: change.path) }
                catch { failures[change.path] = (error as? MarginError) ?? .io("\(error)") }
            }
        }
        return failures
    }

    // MARK: Queries

    public var count: Int { byPath.count }

    public var allNotes: [NoteRecord] { byPath.values.sorted { $0.path < $1.path } }

    public func note(byPath path: String) -> NoteRecord? { byPath[path] }

    public func note(byID id: NoteID) -> NoteRecord? { idToPath[id].flatMap { byPath[$0] } }

    /// The task with `id`. When an id is used more than once (a copy-pasted line, see
    /// `duplicateTaskIDs()`), the first by note path and line wins, the same rule the
    /// `IDAssignmentPass` applies when it reassigns the later ones.
    public func task(byID id: String) -> TaskItem? {
        for path in Set(taskPaths[id] ?? []).sorted() {
            if let t = byPath[path]?.tasks.first(where: { $0.id == id }) { return t }
        }
        return nil
    }

    /// Task ids used more than once, with all their locations ordered by path and line.
    public func duplicateTaskIDs() -> [DuplicateID] {
        taskPaths.compactMap { id, paths in
            guard paths.count > 1 else { return nil }
            return DuplicateID(id: id, locations: occurrences(ofTask: id, in: Set(paths)))
        }.sorted { $0.id < $1.id }
    }

    /// Note ids used by more than one note, with the paths ordered; the first path keeps the id in
    /// `note(byID:)`.
    public func duplicateNoteIDs() -> [DuplicateID] {
        var byID: [NoteID: [String]] = [:]
        for r in byPath.values { byID[r.id, default: []].append(r.path) }
        return byID.compactMap { id, paths in
            paths.count > 1 ? DuplicateID(id: id, locations: paths.sorted().map { IDOccurrence(path: $0, line: nil) }) : nil
        }.sorted { $0.id < $1.id }
    }

    /// Notes that still lack a frontmatter id or have tasks without `^id` (candidates for the
    /// `IDAssignmentPass`), ordered by path.
    public func notesNeedingIDs() -> [NoteRecord] {
        allNotes.filter(\.needsIDAssignment)
    }

    private func occurrences(ofTask id: String, in paths: Set<String>) -> [IDOccurrence] {
        var result: [IDOccurrence] = []
        for path in paths.sorted() {
            for t in byPath[path]?.tasks ?? [] where t.id == id {
                result.append(IDOccurrence(path: path, line: t.source.line))
            }
        }
        return result
    }

    public func notes(inCourse course: CourseID) -> [NoteRecord] {
        byPath.values.filter { $0.courseID == course }.sorted { $0.path < $1.path }
    }

    public func summaries(inCourse course: CourseID? = nil) -> [NoteSummary] {
        (course.map { notes(inCourse: $0) } ?? allNotes).map(\.summary)
    }

    /// All tasks, ordered by note path and line. Optionally limited to a course and/or open ones.
    public func tasks(inCourse course: CourseID? = nil, openOnly: Bool = false) -> [TaskItem] {
        var result: [TaskItem] = []
        for record in byPath.values.sorted(by: { $0.path < $1.path }) {
            if let course, record.courseID != course { continue }
            for t in record.tasks where !(openOnly && t.done) { result.append(t) }
        }
        return result
    }

    public func openTasks(inCourse course: CourseID? = nil) -> [TaskItem] {
        tasks(inCourse: course, openOnly: true)
    }

    /// Notes that link to `noteID`, with the source line as context. Ambiguous links count for
    /// every candidate; links from a note to itself are skipped.
    public func backlinks(to noteID: NoteID) -> [IndexedBacklink] {
        guard let target = note(byID: noteID) else { return [] }
        let key = WikilinkExtractor.normalise(target.name)
        var result: [IndexedBacklink] = []
        for sourcePath in (linkers[key] ?? []).sorted() {
            guard let source = byPath[sourcePath], source.id != target.id else { continue }
            for item in source.links where WikilinkExtractor.normalise(item.link.name) == key {
                let hit: Bool
                switch resolve(item.link, from: source) {
                case .resolved(let id): hit = id == target.id
                case .ambiguous(let ids): hit = ids.contains(target.id)
                case .notCreated, .selfLink: hit = false
                }
                if hit {
                    result.append(IndexedBacklink(sourceNoteID: source.id, sourcePath: source.path,
                                                  link: item.link, line: item.link.line,
                                                  snippet: item.snippet))
                }
            }
        }
        return result
    }

    /// Resolution of every outgoing link of a note, in text order.
    public func outgoingLinks(ofPath path: String) -> [(link: Wikilink, resolution: WikilinkResolution)] {
        guard let record = byPath[path] else { return [] }
        return record.links.map { ($0.link, resolve($0.link, from: record)) }
    }

    /// Links whose target note does not exist, ordered by source path and line.
    public func unresolvedLinks() -> [UnresolvedLink] {
        var result: [UnresolvedLink] = []
        for record in byPath.values.sorted(by: { $0.path < $1.path }) {
            for item in record.links {
                if case .notCreated(let target) = resolve(item.link, from: record) {
                    result.append(UnresolvedLink(sourceNoteID: record.id, sourcePath: record.path,
                                                 target: target, line: item.link.line))
                }
            }
        }
        return result
    }

    /// Tag -> number of notes, tags compared case-insensitively (first spelling kept).
    public func tags() -> [String: Int] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for record in byPath.values {
            for tag in Set(record.tags.map { $0.lowercased() }) {
                let name = spelling[tag] ?? record.tags.first { $0.lowercased() == tag } ?? tag
                spelling[tag] = name
                counts[name, default: 0] += 1
            }
        }
        return counts
    }

    public func notes(withTag tag: String) -> [NoteRecord] {
        let t = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        return byPath.values.filter { $0.tags.contains { $0.caseInsensitiveCompare(t) == .orderedSame } }
            .sorted { $0.path < $1.path }
    }

    // MARK: Internals

    private func resolve(_ link: Wikilink, from source: NoteRecord) -> WikilinkResolution {
        if link.isSelfLink { return .selfLink }
        let key = WikilinkExtractor.normalise(link.name)
        let candidates = (pathsByName[key] ?? []).compactMap { byPath[$0]?.ref }
        return wikilinks.resolve(link, from: source.courseID, in: candidates)
    }

    private func insert(_ record: NoteRecord) {
        byPath[record.path] = record
        if let existing = idToPath[record.id], existing < record.path {} else {
            idToPath[record.id] = record.path
        }
        for t in record.tasks { taskPaths[t.id, default: []].append(record.path) }
        pathsByName[WikilinkExtractor.normalise(record.name), default: []].insert(record.path)
        for item in record.links where !item.link.isSelfLink {
            linkers[WikilinkExtractor.normalise(item.link.name), default: []].insert(record.path)
        }
    }

    private func detach(_ record: NoteRecord) {
        byPath[record.path] = nil
        if idToPath[record.id] == record.path {
            idToPath[record.id] = byPath.values.filter { $0.id == record.id }.map(\.path).min()
        }
        for t in record.tasks {
            taskPaths[t.id]?.removeAll { $0 == record.path }
            if taskPaths[t.id]?.isEmpty == true { taskPaths[t.id] = nil }
        }
        let name = WikilinkExtractor.normalise(record.name)
        pathsByName[name]?.remove(record.path)
        if pathsByName[name]?.isEmpty == true { pathsByName[name] = nil }
        for item in record.links {
            let key = WikilinkExtractor.normalise(item.link.name)
            linkers[key]?.remove(record.path)
            if linkers[key]?.isEmpty == true { linkers[key] = nil }
        }
    }

    private func makeRecord(path: String, text: String) -> NoteRecord {
        let (fm, body) = Frontmatter.parse(text)
        let scan = scanner.scan(text)
        let name = Self.name(ofPath: path)
        let (semester, folderCourse) = Self.folderCourse(ofPath: path)
        let className = fm?.className
        let courseID = folderCourse ?? className.map(Self.slug)
        let stableID = fm.flatMap(IDAssigner.noteID(of:))
        let id = stableID ?? Self.stripExtension(path)

        var properties: [String: FrontmatterValue] = [:]
        if let fm { for key in fm.keys { properties[key] = fm.value(for: key) } }

        let h1 = scan.headings.first { $0.level == 1 }?.text
        let title = (h1?.isEmpty == false ? h1 : nil) ?? name

        var tasks: [TaskItem] = []
        var tasksWithoutID = 0
        for t in extractor.extract(from: scan) {
            if t.blockID == nil { tasksWithoutID += 1 }
            tasks.append(extractor.taskItem(t, noteID: id, courseID: courseID))
        }

        var links: [IndexedLink] = []
        var images = 0
        let wl = wikilinks.extract(from: scan)
        if !wl.isEmpty {
            let lines = WikilinkExtractor.splitLines(text)
            for link in wl where !(link.isEmbed && Self.isImage(link.target)) {
                let raw = link.line - 1 < lines.count ? lines[link.line - 1] : ""
                links.append(IndexedLink(link: link, snippet: WikilinkExtractor.snippet(raw)))
            }
        }
        for l in scan.links where l.isEmbed && Self.isImage(l.inner) { images += 1 }

        return NoteRecord(
            id: id, hasStableID: stableID != nil, tasksWithoutID: tasksWithoutID,
            path: path, title: title, courseID: courseID, semesterID: semester,
            className: className, kind: fm?.kind ?? .note, tags: fm?.tags ?? [], date: fm?.date,
            properties: properties, headings: scan.headings, tasks: tasks, links: links,
            wordCount: Self.wordCount(body), imageCount: images, snippet: Self.snippet(body),
            contentHash: Self.hash(text), text: text)
    }

    // MARK: Static helpers

    static func isMarkdown(_ path: String) -> Bool { path.lowercased().hasSuffix(".md") }

    static func hash(_ text: String) -> String { ContentHash(of: text).hex }

    static func name(ofPath path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return stripExtension(last)
    }

    static func stripExtension(_ path: String) -> String {
        path.lowercased().hasSuffix(".md") ? String(path.dropLast(3)) : path
    }

    /// `<semester>/<course>/…/<file>.md` (at least three components).
    static func folderCourse(ofPath path: String) -> (SemesterID?, CourseID?) {
        let parts = path.split(separator: "/")
        guard parts.count >= 3 else { return (nil, nil) }
        return (String(parts[0]), String(parts[1]))
    }

    static func slug(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).joined(separator: "-")
    }

    static func isImage(_ target: String) -> Bool {
        let ext = target.split(separator: "|").first.map { $0.split(separator: ".").last.map { $0.lowercased() } ?? "" } ?? ""
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tiff"].contains(ext)
    }

    static func wordCount(_ body: String) -> Int {
        var n = 0
        var inWord = false
        for u in body.utf8 {
            let space = u == 0x20 || u == 0x0A || u == 0x0D || u == 0x09
            if space { inWord = false } else if !inWord { inWord = true; n += 1 }
        }
        return n
    }

    static func snippet(_ body: String) -> String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: true).prefix(40) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("```") || t.hasPrefix("- [") { continue }
            return t.count > 160 ? String(t.prefix(160)) + "…" : t
        }
        return ""
    }
}
