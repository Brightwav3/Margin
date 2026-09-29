import Foundation

/// Keeps wikilinks valid when notes are renamed or moved (spec 05 §1: renaming updates links
/// across the vault, default on; §4: name resolution).
///
/// Plug it in with `VaultStore.addRenameObserver(_:)`. After a rename or move of a note or a
/// folder it rewrites every link that pointed at a moved note:
/// `[[Old]]`, `[[Old|alias]]`, `[[Old#Heading]]`, `[[Old#^block]]`, `[[Folder/Old]]`, `![[Old]]`.
///
/// Rules:
/// - Only links that resolved to exactly one moved note *before* the rename are touched
///   (case-insensitive, same-course-first, like `WikilinkExtractor.resolve`). Ambiguous and
///   not-yet-created links are left alone.
/// - The new target is the shortest form that resolves uniquely to the note afterwards, at least
///   as long as the original (a bare name stays bare while it stays unambiguous, otherwise the
///   folder form is used). A link whose text would not change is not rewritten.
/// - Only the target text is replaced. Alias, heading, block id, embed marker, spacing, line
///   endings and everything outside the link stay byte-identical. Links in code blocks, inline
///   code and frontmatter are never seen (the scanner skips them).
/// - Files are written through `VaultStore.write` (atomic, `expectedVersion`); a note that changed
///   meanwhile is re-read and retried, and reported in `lastReport.failed` when it keeps changing.
///
/// Attachments (`![[pic.png]]`) are not handled: only markdown notes are tracked.
public actor WikilinkRewriter: RenameObserver {
    /// What the last rename did.
    public struct Report: Sendable, Equatable {
        public var notesRewritten: [VaultPath] = []
        public var linksRewritten = 0
        /// Notes that could not be rewritten (unreadable, or changed too often while rewriting).
        public var failed: [VaultPath] = []
        public init() {}
    }

    public private(set) var lastReport = Report()
    private let isEnabled: Bool
    private let extractor = WikilinkExtractor()
    private static let maxAttempts = 3

    /// - Parameter isEnabled: the "update links on rename" setting (default on).
    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    private struct Move {
        let oldPath: String   // vault path without `.md`
        let newPath: String
        var oldName: String { oldPath.split(separator: "/").last.map(String.init) ?? oldPath }
    }

    public func vaultDidRename(from: VaultPath, to: VaultPath, isDirectory: Bool, in store: VaultStore) async {
        lastReport = Report()
        guard isEnabled else { return }
        guard let notes = try? await store.list() else { return }

        // Moved notes: new path -> old path.
        var moves: [String: Move] = [:]
        if isDirectory {
            for note in notes where note.isInside(to) {
                let old = from.components + note.components.dropFirst(to.components.count)
                let m = Move(oldPath: Self.stripExt(old.joined(separator: "/")), newPath: Self.stripExt(note.rawValue))
                moves[note.rawValue] = m
            }
        } else if to.pathExtension == "md", from.pathExtension == "md" {
            moves[to.rawValue] = Move(oldPath: Self.stripExt(from.rawValue), newPath: Self.stripExt(to.rawValue))
        }
        guard !moves.isEmpty else { return }

        // Resolution worlds. Note IDs are the paths, so a moved note has a different ID in each.
        let oldToNew = Dictionary(uniqueKeysWithValues: moves.values.map { ($0.oldPath, $0.newPath) })
        let after = notes.map { Self.ref(for: Self.stripExt($0.rawValue)) }
        let before = notes.map { Self.ref(for: moves[$0.rawValue]?.oldPath ?? Self.stripExt($0.rawValue)) }
        let world = World(moves: moves, oldToNew: oldToNew, before: before, after: after,
                          moveNames: Set(moves.values.map { WikilinkExtractor.normalise($0.oldName) }))

        for note in notes {
            let originalPath = moves[note.rawValue]?.oldPath ?? Self.stripExt(note.rawValue)
            await rewrite(note, sourceBefore: originalPath, world: world, in: store)
        }
    }

    // MARK: - Per note

    private struct World {
        let moves: [String: Move]
        let oldToNew: [String: String]
        let before: [NoteRef]
        let after: [NoteRef]
        let moveNames: Set<String>
    }

    private func rewrite(_ note: VaultPath, sourceBefore: String, world: World, in store: VaultStore) async {
        for _ in 0..<Self.maxAttempts {
            let content: String
            let version: ContentHash
            do { (content, version) = try await store.read(note) } catch {
                // Not text (or vanished): nothing to rewrite.
                if case MarginError.invalid = error { return }
                if case MarginError.notFound = error { return }
                lastReport.failed.append(note)
                return
            }
            // Cheap prefilter: skip notes that cannot mention any moved note.
            guard content.contains("[[") else { return }
            guard let (updated, count) = rewritten(content, sourceBefore: sourceBefore,
                                                   sourceAfter: Self.stripExt(note.rawValue), world: world) else { return }
            do {
                try await store.write(note, content: updated, expectedVersion: version)
                lastReport.notesRewritten.append(note)
                lastReport.linksRewritten += count
                return
            } catch MarginError.conflict {
                continue   // changed meanwhile: re-read and recompute
            } catch {
                lastReport.failed.append(note)
                return
            }
        }
        lastReport.failed.append(note)
    }

    /// The text with the affected links rewritten, or `nil` when nothing changes.
    private func rewritten(_ text: String, sourceBefore: String, sourceAfter: String, world: World) -> (String, Int)? {
        let links = extractor.extract(from: text)
        let courseBefore = Self.course(of: sourceBefore)
        let courseAfter = Self.course(of: sourceAfter)
        var edits: [(range: Range<Int>, replacement: [UInt8])] = []
        let bytes = Array(text.utf8)

        for link in links where !link.isSelfLink {
            guard world.moveNames.contains(WikilinkExtractor.normalise(link.name)) else { continue }
            guard case .resolved(let oldID) = extractor.resolve(link, from: courseBefore, in: world.before),
                  let newPath = world.oldToNew[oldID] else { continue }

            let components = newPath.split(separator: "/").map(String.init)
            var target = newPath
            for depth in min(max(link.target.split(separator: "/").count, 1), components.count)...components.count {
                let candidate = components.suffix(depth).joined(separator: "/")
                var probe = link
                probe.target = candidate
                if case .resolved(let id) = extractor.resolve(probe, from: courseAfter, in: world.after), id == newPath {
                    target = candidate
                    break
                }
            }
            guard target != link.target, let edit = Self.edit(for: link, newTarget: target, in: bytes) else { continue }
            edits.append(edit)
        }
        guard !edits.isEmpty else { return nil }

        var out = bytes
        for e in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            out.replaceSubrange(e.range, with: e.replacement)
        }
        return (String(decoding: out, as: UTF8.self), edits.count)
    }

    /// Byte edit that swaps only the target part of `link` (inside `[[ ]]`, before `#` or `|`),
    /// keeping surrounding whitespace, a `.md` suffix and everything after. `nil` when the source
    /// bytes are not laid out as the extractor reported (then the link is left alone).
    private static func edit(for link: Wikilink, newTarget: String, in bytes: [UInt8]) -> (range: Range<Int>, replacement: [UInt8])? {
        let start = link.range.start + (link.isEmbed ? 1 : 0) + 2
        let innerEnd = link.range.end - 2
        guard start <= innerEnd, innerEnd <= bytes.count else { return nil }
        var segEnd = start
        while segEnd < innerEnd, bytes[segEnd] != 0x23, bytes[segEnd] != 0x7C { segEnd += 1 }
        if segEnd < innerEnd, bytes[segEnd] == 0x7C, segEnd > start, bytes[segEnd - 1] == 0x5C { segEnd -= 1 }   // `\|`
        var coreStart = start
        var coreEnd = segEnd
        func isBlank(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 }
        while coreStart < coreEnd, isBlank(bytes[coreStart]) { coreStart += 1 }
        while coreEnd > coreStart, isBlank(bytes[coreEnd - 1]) { coreEnd -= 1 }
        let core = String(decoding: bytes[coreStart..<coreEnd], as: UTF8.self)
        let hasExt = core.lowercased().hasSuffix(".md")
        guard (hasExt ? String(core.dropLast(3)) : core) == link.target else { return nil }
        return (coreStart..<coreEnd, Array((newTarget + (hasExt ? String(core.suffix(3)) : "")).utf8))
    }

    // MARK: - Helpers

    private static func stripExt(_ path: String) -> String {
        path.lowercased().hasSuffix(".md") ? String(path.dropLast(3)) : path
    }

    /// First folder is the course; a note at the vault root belongs to none.
    private static func course(of path: String) -> CourseID? {
        let parts = path.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : nil
    }

    private static func ref(for path: String) -> NoteRef {
        NoteRef(id: path, courseID: course(of: path), name: path.split(separator: "/").last.map(String.init) ?? path, path: path)
    }
}
