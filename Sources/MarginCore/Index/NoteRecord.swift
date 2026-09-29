import Foundation

/// Provides markdown files to the index without depending on the vault store.
///
/// Paths are vault-relative with `/` separators (`fall-2026/bio/Cell Biology.md`).
public protocol NoteContentSource: Sendable {
    /// All markdown note paths in the vault.
    func listMarkdown() async throws -> [String]
    /// The text of one note. Throws `MarginError.notFound` when the file does not exist.
    func read(_ path: String) async throws -> String
}

/// A wikilink found in a note, with the source line as context.
public struct IndexedLink: Sendable, Hashable {
    public var link: Wikilink
    /// The whole source line, trimmed and truncated (see `Backlink.snippet`).
    public var snippet: String
}

/// Everything the index knows about one note.
public struct NoteRecord: Sendable, Hashable, Identifiable {
    /// The frontmatter `id:` when the note has one (stable across rename, move and edits),
    /// otherwise a path-derived placeholder until the `IDAssignmentPass` has run.
    public var id: NoteID
    /// `true` when `id` comes from the note's frontmatter.
    public var hasStableID: Bool
    /// Number of tasks whose id is still a location-derived placeholder (no `^id` on the line).
    public var tasksWithoutID: Int
    /// Vault-relative path including `.md`.
    public var path: String
    public var title: String
    /// Folder-derived course id (`<semester>/<course>/…`), else a slug of `class:`.
    public var courseID: CourseID?
    /// Semester folder (`fall-2026`) when the note lives in `<semester>/<course>/`.
    public var semesterID: SemesterID?
    /// Bare course name from `class:` frontmatter.
    public var className: String?
    public var kind: NoteKind
    public var tags: [String]
    public var date: LocalDate?
    /// All frontmatter entries by key.
    public var properties: [String: FrontmatterValue]
    public var headings: [MarkdownHeading]
    public var tasks: [TaskItem]
    public var links: [IndexedLink]
    public var wordCount: Int
    public var imageCount: Int
    public var snippet: String
    public var contentHash: String
    /// The indexed text (kept for rename and backlink context).
    var text: String
    /// Number of lines the frontmatter block takes in front of the body (line numbers in the
    /// scanner output are file lines; `Note.text` starts after them).
    var bodyLineOffset: Int = 0

    /// `true` when the `IDAssignmentPass` would change this note.
    public var needsIDAssignment: Bool { !hasStableID || tasksWithoutID > 0 }

    /// File name without extension.
    public var name: String { NoteIndex.name(ofPath: path) }

    var ref: NoteRef {
        NoteRef(id: id, courseID: courseID, name: name, path: NoteIndex.stripExtension(path))
    }

    public var summary: NoteSummary {
        NoteSummary(id: id, courseID: courseID, title: title, kind: kind, date: date,
                    snippet: snippet, wordCount: wordCount,
                    openTasks: tasks.lazy.filter { !$0.done }.count, totalTasks: tasks.count,
                    imageCount: imageCount, isPlaceholder: false, modified: nil)
    }
}

/// A backlink to a note, with the source note and line context.
public struct IndexedBacklink: Sendable, Hashable {
    public var sourceNoteID: NoteID
    public var sourcePath: String
    public var link: Wikilink
    public var line: Int
    public var snippet: String
}

/// A link whose target does not exist yet.
public struct UnresolvedLink: Sendable, Hashable {
    public var sourceNoteID: NoteID
    public var sourcePath: String
    public var target: String
    public var line: Int
}

/// Where an id occurs.
public struct IDOccurrence: Sendable, Hashable {
    public var path: String
    /// 1-based line for a task, `nil` for a note.
    public var line: Int?
}

/// An id that is used more than once in the vault.
public struct DuplicateID: Sendable, Hashable {
    public var id: String
    /// All uses, ordered by path and line; the first one keeps the id.
    public var locations: [IDOccurrence]
}
