import Foundation

/// Archives and restores whole semesters (M10-13.B, M11-04.B; spec 05 §1).
///
/// Archiving moves the semester folder `Fall 2026/` to `_archive/Fall 2026/` and sets
/// `"archived": true` on the semester in `.margin/semesters.json`. Nothing is deleted, so restoring
/// (`archived: false`) moves the folder back and clears the flag, and everything is as it was. The
/// vault model treats a semester as archived when its courses are in `_archive/`; the flag covers a
/// semester without courses.
///
/// Both steps are safe against failure: a target folder that exists is `.conflict` before anything
/// moves, and when the move fails after `semesters.json` was written, the old file is put back.
struct SemesterArchiver {
    static let folderName = "_archive"
    static let semestersFile = ".margin/semesters.json"

    let store: VaultStore

    /// The result of `setArchived`.
    struct Outcome: Sendable {
        var entries: [ChangeSet.Entry]
        /// Live and archived folder of the semester, when a folder moved.
        var moved: (from: VaultPath, to: VaultPath)?
    }

    /// Archives (`archived == true`) or restores `semester`. With `dryRun` only the outcome is computed.
    /// - Throws: `.conflict` when the target folder exists, `.invalid` for a semester name that is no
    ///   folder name, `.io` on disk errors.
    func setArchived(_ archived: Bool, semester: Semester, dryRun: Bool) async throws -> Outcome {
        let live = try VaultPath(components: [semester.name])
        let archive = try VaultPath(components: [Self.folderName, semester.name])
        let (from, to) = archived ? (live, archive) : (archive, live)
        let folderExists = await store.exists(from)
        if folderExists, await store.exists(to) { throw MarginError.conflict("\(to) already exists") }

        let file = try VaultPath(Self.semestersFile)
        let old = try? await store.read(file)
        let newJSON = try Self.updatedJSON(old?.content, semester: semester, archived: archived)
        var entries: [ChangeSet.Entry] = []
        if folderExists { entries.append(.init(path: to.rawValue, kind: .moved, fromPath: from.rawValue)) }
        entries.append(.init(path: file.rawValue, kind: old == nil ? .created : .modified, beforeHash: old?.version.hex,
                             afterHash: ContentHash(of: newJSON).hex))
        let outcome = Outcome(entries: entries, moved: folderExists ? (from, to) : nil)
        if dryRun { return outcome }

        if let old { try await store.write(file, content: newJSON, expectedVersion: old.version) }
        else { try await store.create(file, content: newJSON) }
        if folderExists {
            do { try await store.rename(from, to: to) } catch {
                if let old { _ = try? await store.write(file, content: old.content) }   // put the flag back
                throw error
            }
        }
        return outcome
    }

    /// `semesters.json` with the archived flag of `semester` set. Other semesters of the file are kept; a semester that is not in the file yet is added with its current dates.
    static func updatedJSON(_ existing: String?, semester: Semester, archived: Bool) throws -> String {
        var list: [Semester] = []
        if let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do { list = try JSONDecoder().decode([Semester].self, from: Data(existing.utf8)) }
            catch { throw MarginError.invalid("\(semestersFile) is not valid, not touching it: \(error)") }
        }
        var target = semester
        target.isArchived = archived
        if let i = list.firstIndex(where: { $0.id == semester.id || $0.name == semester.name }) {
            list[i].isArchived = archived
        } else {
            list.append(target)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(list), as: UTF8.self) + "\n"
    }
}
