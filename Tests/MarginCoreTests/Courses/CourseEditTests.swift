import Foundation
import Testing
@testable import MarginCore

/// M10-12.B: renaming a course and changing its colour and icon are written to `_course.md` as a
/// lossless frontmatter edit, survive a restart, and a folder rename keeps ids and links intact.
@Suite struct CourseEditTests {
    /// A hand-written `_course.md` with a comment, an unknown key and a body: nothing but the edited
    /// keys may change.
    private static let handWritten = """
        ---
        # my own comment
        name: Cell Biology
        code: BIO 201
        custom-key: [1, 2, three]
        color: bio    # the green one
        icon: eco
        professor: Dr. Okafor
        sessions:
          - {day: Tue, time: "10:00", length: 1.5, kind: Lecture}
        ---

        # Cell Biology

        Body text stays.

        """

    private func seededVault() async throws -> CourseVault {
        let dir = TempDir()
        try dir.seed("Fall 2026/Cell Biology/_course.md", Data(Self.handWritten.utf8))
        try dir.seed("Fall 2026/Cell Biology/Glossary.md", Data("# Glossary\n".utf8))
        try dir.seed("Fall 2026/Modern Europe/_course.md", Data("---\nname: Modern Europe\ncolor: hist\n---\n".utf8))
        try dir.seed("Fall 2026/Modern Europe/Linker.md", Data("---\nclass: \"[[Modern Europe]]\"\n---\nSee [[Cell Biology/Glossary]] and [[Glossary|the terms]].\n".utf8))
        try dir.seed(".margin/semesters.json", Data(SampleVaultGenerator.semestersJSON(Fixtures.week5.semester).utf8))
        return try await CourseVault.reopen(dir)
    }

    private func lines(_ s: String) -> [String] { s.components(separatedBy: "\n") }

    @Test func aRenameChangesOnlyTheNameLine() async throws {
        let v = try await seededVault()
        let before = v.text("Fall 2026/Cell Biology/_course.md")
        #expect(before == Self.handWritten)
        let id = try await v.catalog.courses(query: "cell").first?.id
        #expect(id == "cell-biology")

        let cs = try await v.writer.rename(id: "cell-biology", to: "Molecular Biology", renameFolder: false, actor: .user,
                                           baseVersion: nil, dryRun: false, idempotencyKey: nil)
        let after = v.text("Fall 2026/Cell Biology/_course.md")
        let changed = zip(lines(before), lines(after)).enumerated().filter { $0.element.0 != $0.element.1 }
        #expect(lines(before).count == lines(after).count)
        #expect(changed.count == 1 && changed[0].element.1 == "name: Molecular Biology", "\(changed)")
        #expect(cs.entries.count == 1 && cs.entries[0].afterHash == ContentHash(of: after).hex)
        #expect(cs.entries[0].beforeHash == ContentHash(of: before).hex)
        // Nothing else was created or left behind.
        #expect(v.dir.temporaryFiles.isEmpty)
        await v.shutdown()

        let restarted = try await CourseVault.reopen(v.dir)
        let course = try await restarted.catalog.course(id: "cell-biology")
        #expect(course.name == "Molecular Biology" && course.code == "BIO 201" && course.style.color == "bio")
        await restarted.shutdown()
    }

    @Test func colourAndIconChangeOnlyTheirLines() async throws {
        let v = try await seededVault()
        let before = v.text("Fall 2026/Cell Biology/_course.md")
        _ = try await v.writer.setStyle(id: "cell-biology", icon: "science", color: "econ", actor: .user, baseVersion: nil,
                                        dryRun: false, idempotencyKey: nil)
        let after = v.text("Fall 2026/Cell Biology/_course.md")
        let changed = zip(lines(before), lines(after)).filter { $0 != $1 }.map(\.1)
        // (The frontmatter writer keeps a trailing comment only behind quoted values, so this one goes.)
        #expect(changed == ["color: econ", "icon: science"], "\(changed)")
        await v.shutdown()

        let restarted = try await CourseVault.reopen(v.dir)
        let course = try await restarted.catalog.course(id: "cell-biology")
        #expect(course.style == CoursePalette.style(icon: "science", color: "econ"))
        await restarted.shutdown()
    }

    @Test func aKeyThatIsMissingIsAppended() async throws {
        let dir = TempDir()
        try dir.seed("Fall 2026/Bare/_course.md", Data("---\nname: Bare\n---\n\nBody\n".utf8))
        try dir.seed(".margin/semesters.json", Data(SampleVaultGenerator.semestersJSON(Fixtures.week5.semester).utf8))
        let v = try await CourseVault.reopen(dir)
        _ = try await v.writer.setStyle(id: "bare", icon: "school", color: "phil", actor: .user, baseVersion: nil,
                                        dryRun: false, idempotencyKey: nil)
        #expect(v.text("Fall 2026/Bare/_course.md") == "---\nname: Bare\nicon: school\ncolor: phil\n---\n\nBody\n")
        await v.shutdown()
    }

    @Test func renamingTheFolderKeepsTheIdLinksAndNotes() async throws {
        let v = try await seededVault()
        let linker = "Fall 2026/Modern Europe/Linker.md"
        let notesBefore = try await v.notes.notes(course: "cell-biology").map(\.title)
        #expect(notesBefore == ["Glossary"])

        let cs = try await v.writer.rename(id: "cell-biology", to: "Molecular Biology", renameFolder: true, actor: .user,
                                           baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(cs.entries.map(\.kind) == [.moved])
        #expect(!v.dir.exists("Fall 2026/Cell Biology") && v.dir.exists("Fall 2026/Molecular Biology/Glossary.md"))
        // The id was pinned in the file, so it does not follow the folder name.
        let file = v.text("Fall 2026/Molecular Biology/_course.md")
        #expect(file.contains("id: cell-biology") && file.contains("name: Molecular Biology"))
        #expect(file.contains("# my own comment") && file.contains("custom-key: [1, 2, three]") && file.hasSuffix("Body text stays.\n"))
        // Links into the folder were rewritten through the rename observer; the bare link still resolves.
        let text = v.text(linker)
        #expect(text.contains("[[Molecular Biology/Glossary]]") && text.contains("[[Glossary|the terms]]"), "\(text)")

        let course = try await v.catalog.course(id: "cell-biology")
        #expect(course.name == "Molecular Biology")
        #expect(try await v.notes.notes(course: "cell-biology").map(\.title) == notesBefore)
        await v.shutdown()

        let restarted = try await CourseVault.reopen(v.dir)
        #expect(try await restarted.catalog.course(id: "cell-biology").name == "Molecular Biology")
        #expect(try await restarted.notes.notes(course: "cell-biology").map(\.title) == notesBefore)
        await restarted.shutdown()
    }

    @Test func aTakenFolderIsNeverOverwritten() async throws {
        let v = try await seededVault()
        let before = v.dir.snapshot()
        let code = await errorCode { try await v.writer.rename(id: "cell-biology", to: "modern europe", renameFolder: true, actor: .user,
                                                               baseVersion: nil, dryRun: false, idempotencyKey: nil) }
        #expect(code == "conflict")
        try v.dir.seed("Fall 2026/Elsewhere/Notes.md", Data("x".utf8))            // a folder with no course file
        let code2 = await errorCode { try await v.writer.rename(id: "cell-biology", to: "Elsewhere", renameFolder: true, actor: .user,
                                                                baseVersion: nil, dryRun: false, idempotencyKey: nil) }
        #expect(code2 == "conflict")
        var after = v.dir.snapshot(); after["Fall 2026/Elsewhere/Notes.md"] = nil
        #expect(after == before)
        await v.shutdown()
    }

    @Test func aCaseOnlyFolderRenameWorks() async throws {
        let v = try await seededVault()
        _ = try await v.writer.rename(id: "cell-biology", to: "CELL BIOLOGY", renameFolder: true, actor: .user, baseVersion: nil,
                                      dryRun: false, idempotencyKey: nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: v.dir.file("Fall 2026").path)
        #expect(names.contains("CELL BIOLOGY") && !names.contains("Cell Biology"))
        #expect(try await v.catalog.course(id: "cell-biology").name == "CELL BIOLOGY")
        await v.shutdown()
    }

    @Test func aStaleVersionAndADryRunTouchNothing() async throws {
        let v = try await seededVault()
        let before = v.dir.snapshot()
        let version = try await v.writer.courseVersion(id: "cell-biology")
        #expect(version == ContentHash(of: Self.handWritten).hex)
        let dry = try await v.writer.rename(id: "cell-biology", to: "Renamed", renameFolder: true, actor: .user,
                                            baseVersion: version, dryRun: true, idempotencyKey: nil)
        #expect(dry.isDryRun && dry.entries.count == 1 && dry.entries[0].kind == .moved)
        let stale = await errorCode { try await v.writer.setStyle(id: "cell-biology", icon: "x", color: nil, actor: .user, baseVersion: "0000",
                                                                  dryRun: false, idempotencyKey: nil) }
        #expect(stale == "conflict")
        #expect(v.dir.snapshot() == before)
        await v.shutdown()
    }

    @Test func aFileEditedMeanwhileIsNotOverwritten() async throws {
        let v = try await seededVault()
        let version = try await v.writer.courseVersion(id: "cell-biology")
        // Another program changes the file after the caller read the version.
        try v.dir.seed("Fall 2026/Cell Biology/_course.md", Data((Self.handWritten + "Added by hand.\n").utf8))
        let code = await errorCode { try await v.writer.setStyle(id: "cell-biology", icon: "science", color: nil, actor: .user,
                                                                 baseVersion: version, dryRun: false, idempotencyKey: nil) }
        #expect(code == "conflict")
        #expect(v.text("Fall 2026/Cell Biology/_course.md").hasSuffix("Added by hand.\n"))
        await v.shutdown()
    }

    @Test func aBrokenFileIsStillEditableButNotMadeWorse() async throws {
        let dir = TempDir()
        // No `name:` (the folder name is used), a duplicate key: both are problems the app did not cause.
        try dir.seed("Fall 2026/Odd/_course.md", Data("---\ncode: X\ncode: Y\n---\n".utf8))
        try dir.seed(".margin/semesters.json", Data(SampleVaultGenerator.semestersJSON(Fixtures.week5.semester).utf8))
        let v = try await CourseVault.reopen(dir)
        _ = try await v.writer.setStyle(id: "odd", icon: nil, color: "bio", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(v.text("Fall 2026/Odd/_course.md").contains("color: bio"))
        await v.shutdown()
    }
}
