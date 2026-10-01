import Foundation
import Testing
@testable import MarginCore

/// One suite, run against `FixtureNoteRepository` and `VaultNoteRepository` (contract §5).
@Suite struct NoteRepositoryConformanceTests {
    @Test(arguments: HarnessKind.allCases)
    func renameMovesTheFileRetitlesAndKeepsTheID(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let id: NoteID = "bio/lecture-8"
            let before = try await h.notes.filePath(id: id)
            #expect(before.hasSuffix("Cell Biology/Lecture 8 — Cell membrane.md"))
            let probe = try await h.notes.create(course: "bio", title: "Link probe", kind: .note,
                                                 text: "See [[Lecture 8 — Cell membrane]] and [[Lecture 8 — Cell membrane|it]].\n",
                                                 actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil).entries[0].noteID!
            let dry = try await h.notes.rename(id: id, to: "Membranes", actor: .user, baseVersion: nil, dryRun: true, idempotencyKey: nil)
            #expect(dry.entries.count == 1 && dry.entries[0].kind == .moved)
            #expect(try await h.notes.filePath(id: id) == before)
            let cs = try await h.notes.rename(id: id, to: "Membranes", actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(cs.entries[0].fromPath == before && cs.entries[0].path.hasSuffix("Cell Biology/Membranes.md"))
            #expect(try await h.notes.filePath(id: id).hasSuffix("Cell Biology/Membranes.md"))
            let note = try await h.notes.open(id: id)
            #expect(note.summary.title == "Membranes" && note.text.contains("# Membranes"))
            let linking = try await h.notes.open(id: probe).text
            #expect(linking.contains("[[Membranes]]") && linking.contains("[[Membranes|it]]"), "\(linking)")
            // Same title again: nothing to do. Another note's name: conflict. Empty: invalid.
            #expect(try await h.notes.rename(id: id, to: "Membranes", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil).isEmpty)
            do { _ = try await h.notes.rename(id: id, to: "Glossary", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil); Issue.record("no conflict") }
            catch let e as MarginError { #expect(e.code == "conflict") }
            do { _ = try await h.notes.rename(id: id, to: "  ", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil); Issue.record("no error") }
            catch let e as MarginError { #expect(e.code == "invalid") }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func embeddedFilesAreFoundLikeObsidianDoes(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            // Every implementation: unknown names are not found, names leaving the vault are refused.
            await #expect(throws: MarginError.self) { _ = try await h.notes.attachment(named: "missing.png", near: "bio/lecture-8") }
            for bad in ["../secret.png", ".margin/settings.json", "/etc/hosts", ""] {
                do { _ = try await h.notes.attachment(named: bad, near: nil); Issue.record("\(bad) was read") }
                catch let e as MarginError { #expect(e.code == "invalid", "\(bad)") }
            }
            guard kind == .vault else { return }
            // Next to the note, in `_files/`, then anywhere by name.
            try h.writeFile("Fall 2026/Cell Biology/_files/membrane.png", "PNG-1")
            try h.writeFile("Fall 2026/Modern Europe/map.png", "PNG-2")
            let near = try await h.notes.attachment(named: "membrane.png", near: "bio/lecture-8")
            #expect(String(decoding: near, as: UTF8.self) == "PNG-1")
            #expect(String(decoding: try await h.notes.attachment(named: "MAP.png", near: "bio/lecture-8"), as: UTF8.self) == "PNG-2")
            #expect(String(decoding: try await h.notes.attachment(named: "Fall 2026/Modern Europe/map.png", near: nil), as: UTF8.self) == "PNG-2")
        }
    }

    let world = Fixtures.week5

    private static let bioIDs = [
        "bio/lecture-9", "bio/lecture-8", "bio/lecture-7", "bio/lab-2", "bio/lecture-6", "bio/lecture-5",
        "bio/assignments", "bio/glossary", "bio/membrane-transport-summary", "bio/midterm-formula-sheet",
    ]

    // MARK: Reading

    @Test(arguments: HarnessKind.allCases)
    func notesOfACourseAreDatedNewestFirstThenUndatedByTitle(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let bio = try await h.notes.notes(course: "bio")
            #expect(bio.map(\.id) == Self.bioIDs)
            let all = try await h.notes.notes(course: nil)
            #expect(all.count == world.allNotes.count)         // no _course.md, _grades.md or inbox
            #expect(all.count == 19)
            #expect(Set(all.map(\.id)) == Set(world.allNotes.map(\.id)))
            // A stable order: asking twice gives the same list.
            let again = try await h.notes.notes(course: nil)
            #expect(again.map(\.id) == all.map(\.id))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func summariesCarryTheFixtureValues(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let byID = Dictionary(uniqueKeysWithValues: try await h.notes.notes(course: nil).map { ($0.id, $0) })
            for expected in world.allNotes {
                let s = try #require(byID[expected.id], "missing \(expected.id)")
                #expect(s.courseID == expected.courseID, "\(expected.id) course")
                #expect(s.title == expected.title, "\(expected.id) title")
                #expect(s.kind == expected.kind, "\(expected.id) kind")
                #expect(s.date == expected.date, "\(expected.id) date")
                #expect(s.openTasks == expected.openTasks, "\(expected.id) open")
                #expect(s.totalTasks == expected.totalTasks, "\(expected.id) total")
                #expect(s.imageCount == expected.imageCount, "\(expected.id) images")
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func openReturnsTheBodyWithoutFrontmatter(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = try await h.notes.open(id: "bio/lecture-8")
            #expect(note.id == "bio/lecture-8")
            #expect(note.text == world.markdownBody(of: "bio/lecture-8"))
            #expect(note.text.hasPrefix("# Lecture 8 — Cell membrane\n"))
            #expect(!note.text.hasPrefix("---"))
            #expect(!note.version.isEmpty)
            #expect(note.summary.courseID == "bio")
            let again = try await h.notes.open(id: "bio/lecture-8")
            #expect(again.version == note.version)
            let other = try await h.notes.open(id: "bio/glossary")
            #expect(other.version != note.version)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func unknownNoteAndCourseAreNotFound(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            for id in ["nope/nothing", "bio/_course", "bio", ""] {
                do { _ = try await h.notes.open(id: id); Issue.record("open(\(id)) should throw") }
                catch let e as MarginError { #expect(e.code == "notFound", "\(id): \(e)") }
            }
            do { _ = try await h.notes.notes(course: "nope"); Issue.record("notes(course: nope) should throw") }
            catch let e as MarginError { #expect(e.code == "notFound") }
        }
    }

    // MARK: save

    @Test(arguments: HarnessKind.allCases)
    func saveReplacesTheBodyAndReturnsTheChangeSet(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: "bio/glossary")
            let text = "# Glossary\n\nTerms to know.\n\n- [ ] Learn the terms @2026-09-30\n"
            let cs = try await h.notes.save(id: "bio/glossary", text: text, actor: testActor,
                                            baseVersion: before.version, dryRun: false, idempotencyKey: nil)
            #expect(cs.actor == testActor)
            #expect(cs.timestamp == h.clock.now)
            #expect(!cs.isDryRun)
            #expect(cs.entries.count == 1)
            let entry = try #require(cs.entries.first)
            #expect(entry.kind == .modified)
            #expect(entry.noteID == "bio/glossary")
            #expect(entry.path == "Fall 2026/Cell Biology/Glossary.md")
            #expect(entry.beforeHash == before.version)
            let after = try await h.notes.open(id: "bio/glossary")
            #expect(after.text == text)
            #expect(after.version == entry.afterHash)
            #expect(after.version != before.version)
            #expect(after.summary.totalTasks == 1 && after.summary.openTasks == 1)
            #expect(after.summary.snippet == "Terms to know.")
            // The list sees the change too.
            let listed = try await h.notes.notes(course: "bio").first { $0.id == "bio/glossary" }
            #expect(listed?.totalTasks == 1)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func savingIdenticalTextChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = try await h.notes.open(id: "bio/glossary")
            let cs = try await h.notes.save(id: "bio/glossary", text: note.text, actor: .user,
                                            baseVersion: note.version, dryRun: false, idempotencyKey: nil)
            #expect(cs.isEmpty)
            let after = try await h.notes.open(id: "bio/glossary")
            #expect(after.version == note.version)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aStaleBaseVersionIsAConflictAndWritesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            _ = try await h.notes.save(id: "bio/glossary", text: "# Glossary\n\nfirst\n", actor: .user,
                                       baseVersion: v0.version, dryRun: false, idempotencyKey: nil)
            let v1 = try await h.notes.open(id: "bio/glossary")
            do {
                _ = try await h.notes.save(id: "bio/glossary", text: "# Glossary\n\nsecond\n", actor: testActor,
                                           baseVersion: v0.version, dryRun: false, idempotencyKey: nil)
                Issue.record("stale save should throw")
            } catch let e as MarginError { #expect(e.code == "conflict") }
            let after = try await h.notes.open(id: "bio/glossary")
            #expect(after == v1)
            // No base version: the last writer wins.
            _ = try await h.notes.save(id: "bio/glossary", text: "# Glossary\n\nthird\n", actor: .user,
                                       baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let last = try await h.notes.open(id: "bio/glossary")
            #expect(last.text == "# Glossary\n\nthird\n")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func dryRunReportsTheChangeAndChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: "bio/glossary")
            let cs = try await h.notes.save(id: "bio/glossary", text: "# Glossary\n\ndry\n", actor: testActor,
                                            baseVersion: before.version, dryRun: true, idempotencyKey: "dry-1")
            #expect(cs.isDryRun)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .modified)
            #expect(cs.entries[0].beforeHash == before.version)
            let after = try await h.notes.open(id: "bio/glossary")
            #expect(after == before)
            // A dry run does not use up the key: the real write with the same key happens.
            let real = try await h.notes.save(id: "bio/glossary", text: "# Glossary\n\ndry\n", actor: testActor,
                                              baseVersion: before.version, dryRun: false, idempotencyKey: "dry-1")
            #expect(!real.isDryRun)
            #expect(real.entries[0].afterHash == cs.entries[0].afterHash)
            let written = try await h.notes.open(id: "bio/glossary")
            #expect(written.text == "# Glossary\n\ndry\n")
            // A dry run still detects conflicts.
            do {
                _ = try await h.notes.save(id: "bio/glossary", text: "x", actor: .user,
                                           baseVersion: before.version, dryRun: true, idempotencyKey: nil)
                Issue.record("stale dry run should throw")
            } catch let e as MarginError { #expect(e.code == "conflict") }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func aRepeatedIdempotencyKeyWritesOnce(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let v0 = try await h.notes.open(id: "bio/glossary")
            let first = try await h.notes.save(id: "bio/glossary", text: "# Glossary\n\nonce\n", actor: testActor,
                                               baseVersion: v0.version, dryRun: false, idempotencyKey: "k-1")
            // The retry carries the old base version, which would conflict if it wrote again.
            let second = try await h.notes.save(id: "bio/glossary", text: "# Glossary\n\nonce\n", actor: testActor,
                                                baseVersion: v0.version, dryRun: false, idempotencyKey: "k-1")
            #expect(second.id == first.id)
            #expect(second == first)
            let now = try await h.notes.open(id: "bio/glossary")
            #expect(now.version == first.entries[0].afterHash)
            // The same key from another actor is a different request.
            do {
                _ = try await h.notes.save(id: "bio/glossary", text: "# Glossary\n\nother\n", actor: .user,
                                           baseVersion: v0.version, dryRun: false, idempotencyKey: "k-1")
                Issue.record("another actor's request must not reuse the key")
            } catch let e as MarginError { #expect(e.code == "conflict") }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func savingToAnUnknownNoteIsNotFound(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            do {
                _ = try await h.notes.save(id: "nope/nothing", text: "x", actor: .user, baseVersion: nil,
                                           dryRun: false, idempotencyKey: nil)
                Issue.record("should throw")
            } catch let e as MarginError { #expect(e.code == "notFound") }
        }
    }

    // MARK: create

    @Test(arguments: HarnessKind.allCases)
    func createAddsANoteToTheCourse(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.notes.create(course: "bio", title: "Lecture 10 — Transport", kind: .lecture, text: "",
                                              actor: testActor, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let entry = try #require(cs.entries.first)
            #expect(cs.entries.count == 1 && entry.kind == .created)
            #expect(entry.noteID == "bio/lecture-10-transport")
            #expect(entry.path == "Fall 2026/Cell Biology/Lecture 10 — Transport.md")
            #expect(entry.beforeHash == nil)
            let note = try await h.notes.open(id: "bio/lecture-10-transport")
            #expect(note.text == "# Lecture 10 — Transport\n")
            #expect(note.version == entry.afterHash || h.kind == .vault)   // the vault hashes the file with frontmatter
            #expect(note.summary.kind == .lecture && note.summary.courseID == "bio")
            #expect(note.summary.title == "Lecture 10 — Transport")
            let ids = try await h.notes.notes(course: "bio").map(\.id)
            #expect(ids.contains("bio/lecture-10-transport"))
            #expect(ids.count == Self.bioIDs.count + 1)
            // Own text is kept.
            let two = try await h.notes.create(course: "chem", title: "Lab 5", kind: .lab, text: "# Lab 5\n\n- [ ] Prepare\n",
                                               actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let lab = try await h.notes.open(id: try #require(two.entries.first?.noteID))
            #expect(lab.text == "# Lab 5\n\n- [ ] Prepare\n")
            #expect(lab.summary.openTasks == 1)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func createRejectsDuplicatesUnknownCoursesAndEmptyTitles(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            func code(_ course: CourseID, _ title: String) async -> String? {
                do {
                    _ = try await h.notes.create(course: course, title: title, kind: .note, text: "", actor: .user,
                                                 baseVersion: nil, dryRun: false, idempotencyKey: nil)
                    return nil
                } catch let e as MarginError { return e.code } catch { return "other" }
            }
            #expect(await code("bio", "Glossary") == "conflict")
            #expect(await code("nope", "Anything") == "notFound")
            #expect(await code("bio", "   ") == "invalid")
            #expect(await code("bio", "Fresh note") == nil)
            #expect(await code("bio", "Fresh note") == "conflict")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func createDryRunChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let cs = try await h.notes.create(course: "bio", title: "Never written", kind: .note, text: "",
                                              actor: .user, baseVersion: nil, dryRun: true, idempotencyKey: nil)
            #expect(cs.isDryRun && cs.entries.count == 1 && cs.entries[0].kind == .created)
            let ids = try await h.notes.notes(course: "bio").map(\.id)
            #expect(ids == Self.bioIDs)
            do { _ = try await h.notes.open(id: "bio/never-written"); Issue.record("should not exist") }
            catch let e as MarginError { #expect(e.code == "notFound") }
        }
    }

    // MARK: move

    @Test(arguments: HarnessKind.allCases)
    func moveChangesTheCourseAndKeepsTheID(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: "bio/glossary")
            let cs = try await h.notes.move(id: "bio/glossary", toCourse: "chem", actor: testActor,
                                            baseVersion: before.version, dryRun: false, idempotencyKey: nil)
            let entry = try #require(cs.entries.first)
            #expect(cs.entries.count == 1 && entry.kind == .moved)
            #expect(entry.noteID == "bio/glossary")
            #expect(entry.fromPath == "Fall 2026/Cell Biology/Glossary.md")
            #expect(entry.path == "Fall 2026/Organic Chemistry/Glossary.md")
            #expect(entry.beforeHash == before.version && entry.afterHash == before.version)
            let after = try await h.notes.open(id: "bio/glossary")
            #expect(after.summary.courseID == "chem")
            #expect(after.text == before.text)
            #expect(try await h.notes.notes(course: "chem").map(\.id).contains("bio/glossary"))
            #expect(try await !h.notes.notes(course: "bio").map(\.id).contains("bio/glossary"))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func moveErrorsAndNoOps(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            func code(_ id: NoteID, _ course: CourseID, base: String? = nil, dryRun: Bool = false) async -> String? {
                do {
                    _ = try await h.notes.move(id: id, toCourse: course, actor: .user, baseVersion: base, dryRun: dryRun,
                                               idempotencyKey: nil)
                    return nil
                } catch let e as MarginError { return e.code } catch { return "other" }
            }
            #expect(await code("nope/nothing", "chem") == "notFound")
            #expect(await code("bio/glossary", "nope") == "notFound")
            #expect(await code("bio/glossary", "chem", base: "stale") == "conflict")

            // Same course: nothing to do.
            let same = try await h.notes.move(id: "bio/glossary", toCourse: "bio", actor: .user, baseVersion: nil,
                                              dryRun: false, idempotencyKey: nil)
            #expect(same.isEmpty)

            // A note of that name already lives in the target course.
            _ = try await h.notes.create(course: "chem", title: "Glossary", kind: .study, text: "", actor: .user,
                                         baseVersion: nil, dryRun: false, idempotencyKey: nil)
            #expect(await code("bio/glossary", "chem") == "conflict")

            // Dry run: reported, not done.
            let dry = try await h.notes.move(id: "bio/midterm-formula-sheet", toCourse: "math", actor: .user,
                                             baseVersion: nil, dryRun: true, idempotencyKey: nil)
            #expect(dry.isDryRun && dry.entries.count == 1)
            let sheet = try await h.notes.open(id: "bio/midterm-formula-sheet")
            #expect(sheet.summary.courseID == "bio")
        }
    }

    // MARK: delete

    @Test(arguments: HarnessKind.allCases)
    func deleteRemovesTheNote(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: "bio/glossary")
            let cs = try await h.notes.delete(id: "bio/glossary", actor: testActor, baseVersion: before.version,
                                              dryRun: false, idempotencyKey: nil)
            let entry = try #require(cs.entries.first)
            #expect(cs.entries.count == 1 && entry.kind == .deleted)
            #expect(entry.noteID == "bio/glossary")
            #expect(entry.beforeHash == before.version && entry.afterHash == nil)
            #expect(entry.path == "Fall 2026/Cell Biology/Glossary.md")
            do { _ = try await h.notes.open(id: "bio/glossary"); Issue.record("should be gone") }
            catch let e as MarginError { #expect(e.code == "notFound") }
            let ids = try await h.notes.notes(course: nil).map(\.id)
            #expect(!ids.contains("bio/glossary") && ids.count == 18)
            // Deleting again: not found.
            do {
                _ = try await h.notes.delete(id: "bio/glossary", actor: .user, baseVersion: nil, dryRun: false,
                                             idempotencyKey: nil)
                Issue.record("second delete should throw")
            } catch let e as MarginError { #expect(e.code == "notFound") }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func deleteHonoursBaseVersionAndDryRun(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let note = try await h.notes.open(id: "bio/glossary")
            do {
                _ = try await h.notes.delete(id: "bio/glossary", actor: .user, baseVersion: "stale", dryRun: false,
                                             idempotencyKey: nil)
                Issue.record("stale delete should throw")
            } catch let e as MarginError { #expect(e.code == "conflict") }
            let dry = try await h.notes.delete(id: "bio/glossary", actor: .user, baseVersion: note.version, dryRun: true,
                                               idempotencyKey: nil)
            #expect(dry.isDryRun && dry.entries.count == 1)
            let still = try await h.notes.open(id: "bio/glossary")
            #expect(still == note)
        }
    }

    // MARK: externalChanges

    @Test(arguments: HarnessKind.allCases)
    func externalChangesAreDeliveredButOwnWritesAreNot(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let changes = h.notes.externalChanges              // subscribe first
            // The service's own write comes first and must stay silent...
            let mine = try await h.notes.open(id: "bio/lecture-7")
            _ = try await h.notes.save(id: "bio/lecture-7", text: "# Lecture 7 — Organelles\n\nmine\n", actor: .user,
                                       baseVersion: mine.version, dryRun: false, idempotencyKey: nil)
            // ...an outside edit follows and is reported.
            try await h.editNote("bio/glossary", "# Glossary\n\nchanged elsewhere\n")
            let seen = await collect(from: changes) { $0.contains { $0.noteID == "bio/glossary" } }
            let all = seen.flatMap { $0 }
            #expect(all.contains(NoteChange(noteID: "bio/glossary", kind: .modified)), "seen: \(all)")
            #expect(!all.contains { $0.noteID == "bio/lecture-7" }, "own write was reported: \(all)")
            let now = try await h.notes.open(id: "bio/glossary")
            #expect(now.text == "# Glossary\n\nchanged elsewhere\n")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func anExternalDeletionIsReportedAndTheNoteDisappears(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let changes = h.notes.externalChanges
            try await h.deleteNote("bio/glossary")
            let seen = await collect(from: changes) { $0.contains { $0.noteID == "bio/glossary" } }
            #expect(seen.flatMap { $0 }.contains(NoteChange(noteID: "bio/glossary", kind: .deleted)))
            let ids = try await h.notes.notes(course: "bio").map(\.id)
            #expect(!ids.contains("bio/glossary"))
        }
    }
}
