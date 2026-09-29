import Foundation
import Testing
@testable import MarginCore

/// M12-03, corrupted content: notes and course files that are malformed, binary, not UTF-8, full
/// of NUL bytes, huge, or made of extremely long lines. The vault is a hand-edited folder, so any
/// of them can turn up. Required: no crash and no hang in any service, typed errors, and the
/// bytes of a corrupt file never changed by a service (an edit either keeps everything it did not
/// touch or is refused).
@Suite struct CorruptedContentTests {
    struct Sample: Sendable, CustomTestStringConvertible {
        var name: String
        var bytes: Data
        /// Valid UTF-8 (the index can read it). Invalid ones must be left alone and unlisted.
        var utf8: Bool
        var testDescription: String { name }
    }

    static let folder = "Fall 2026/Cell Biology"

    static func repeated(_ s: String, _ n: Int) -> String { String(repeating: s, count: n) }

    static let corpus: [Sample] = {
        var rng = RobustRNG(seed: 0x4D41_5247_494E)
        var garbage = Data([0xFF, 0xFE, 0x00, 0x80])
        for _ in 0..<(64 * 1024) { garbage.append(UInt8(truncatingIfNeeded: rng.next())) }
        var huge = "# Huge note\n\n"
        for i in 0..<40_000 { huge += "Line \(i) of a very large note with [[Lecture 8]] and #tag\(i % 50) inside.\n" }
        for i in 0..<400 { huge += "- [ ] huge task \(i) @2026-10-\(String(format: "%02d", 1 + i % 28))\n" }
        func text(_ s: String) -> Data { Data(s.utf8) }
        return [
            Sample(name: "malformed yaml", bytes: text("---\nid: [unclosed\nname: : :\n\t- tab\n\"quote\n---\n# Malformed YAML\n\n- [ ] Task after bad yaml ^t-bad1\n"), utf8: true),
            Sample(name: "unterminated frontmatter", bytes: text("---\nid: bio/unterminated\ntype: lecture\n\n# Unterminated\n- [ ] still a task ^t-unt1\n"), utf8: true),
            Sample(name: "binary garbage", bytes: garbage, utf8: false),
            Sample(name: "latin-1 bytes", bytes: Data("---\nid: bio/latin1\n---\n# Caf".utf8) + Data([0xE9, 0x0A]), utf8: false),
            Sample(name: "truncated multibyte", bytes: Data("# Cut in the middle ".utf8) + Data([0xE2, 0x82]), utf8: false),
            Sample(name: "nul bytes in the body", bytes: text("---\nid: bio/nul\n---\n# Nul\n\0\0 [[Lecture 8]] \0\n- [ ] task with nul \0 ^t-nul1\n"), utf8: true),
            Sample(name: "nul bytes in the frontmatter", bytes: text("---\nid: bio/nulfm\0\ntitle: a\0b\n---\n# NulFM\n"), utf8: true),
            Sample(name: "one line of a million characters", bytes: text("# Long line\n" + repeated("a", 1_000_000) + " [[Lecture 8]]\n- [ ] after the long line ^t-lng1\n"), utf8: true),
            Sample(name: "two hundred thousand wikilink openers", bytes: text("# Openers\n" + repeated("[[", 200_000) + "x]]\n"), utf8: true),
            Sample(name: "one hundred thousand task markers on a line", bytes: text("# Markers\n" + repeated("- [ ] ", 100_000) + "\n"), utf8: true),
            Sample(name: "two megabytes in one frontmatter line", bytes: text("---\nid: bio/longfm\nblob: " + repeated("x", 2_000_000) + "\n---\n# LongFM\n"), utf8: true),
            Sample(name: "pathological markup", bytes: text("# Markup\n" + repeated("> ", 50_000) + "text\n" + repeated("#", 100_000) + " heading\n" + repeated("*", 200_000) + "\n" + repeated("`", 200_000) + "\n" + repeated("[", 100_000) + "](" + repeated("(", 100_000) + "\n" + repeated("| a ", 50_000) + "|\n"), utf8: true),
            Sample(name: "huge note", bytes: text(huge), utf8: true),
            Sample(name: "byte order mark only", bytes: Data([0xEF, 0xBB, 0xBF]), utf8: true),
            Sample(name: "empty file", bytes: Data(), utf8: true),
            Sample(name: "frontmatter only", bytes: text("---\n---\n"), utf8: true),
            Sample(name: "crlf frontmatter", bytes: text("---\r\nid: bio/crlf\r\n---\r\n# CRLF\r\n- [ ] crlf task ^t-crl1\r\n"), utf8: true),
            Sample(name: "carriage returns only", bytes: text("---\rid: bio/cr\r---\r# CR\r- [ ] cr task ^t-cr01\r"), utf8: true),
            Sample(name: "duplicate id a", bytes: text("---\nid: bio/dup\n---\n# Dup A\n- [ ] dup task ^t-dup1\n"), utf8: true),
            Sample(name: "duplicate id b", bytes: text("---\nid: bio/dup\n---\n# Dup B\n- [ ] dup task ^t-dup1\n"), utf8: true),
            Sample(name: "control characters", bytes: text("# Controls\n\u{1}\u{2}\u{7}\u{1B}[31m red \u{8}\u{7F} \u{FEFF} \u{202E} [[Lecture 8]]\n"), utf8: true),
        ]
    }()

    static func seed(_ dir: TempDir) throws {
        for (i, s) in corpus.enumerated() { try dir.seed("\(folder)/Corrupt \(i) \(s.name).md", s.bytes) }
    }

    /// Bytes of every corpus file, present anywhere in the vault (a folder rename moves them).
    static func corpusIsIntact(in v: RobustVault) -> [String] {
        let present = Set(v.files().values)
        return corpus.filter { !present.contains($0.bytes) }.map(\.name)
    }

    // MARK: Reading

    @Test func everyServiceReadsAVaultFullOfCorruptFiles() async throws {
        let started = Date()
        try await withRobustVault(seed: Self.seed) { v in
            await exerciseReads(v.env)
            let notes = try await v.env.notes.notes(course: nil)
            let ids = Set(notes.map(\.id))
            for fixture in Fixtures.week5.allNotes { #expect(ids.contains(fixture.id), "lost \(fixture.id)") }
            // Files that are not text are not notes; text files are.
            let titles = notes.map(\.title).joined(separator: "|")
            #expect(!titles.contains("Caf"), "a latin-1 file must not be indexed")
            #expect(titles.contains("Dup A") || titles.contains("Dup B"))
            _ = try await v.env.search.search(query: "huge note")
            _ = try await v.env.search.search(query: "wikilink")
            _ = try await v.env.graph.graph(scope: .all, filter: .none)
            _ = try await v.env.tasks.today()
            _ = try await v.env.tasks.upcoming()
            _ = try await v.env.tasks.tasks(course: "bio")
            _ = try await v.env.graph.ego(note: "bio/lecture-8", depth: 2)
            #expect(Self.corpusIsIntact(in: v).isEmpty, "reading changed: \(Self.corpusIsIntact(in: v))")
            #expect(await v.matchesRestart())
        }
        print("corrupt corpus: \(Self.corpus.count) files, \(Self.corpus.reduce(0) { $0 + $1.bytes.count } / 1024) KB, opened and read in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        #expect(Date().timeIntervalSince(started) < 240, "reading the corrupt corpus took too long")
    }

    @Test func aFileThatIsNotUTF8CannotBeOpenedOrWritten() async throws {
        try await withRobustVault(seed: Self.seed) { v in
            let path = "\(Self.folder)/Corrupt 3 latin-1 bytes.md"
            let bytes = try #require(v.dir.bytes(path))
            let store = try await VaultStore.open(root: v.dir.url)
            do { _ = try await store.read(vp(path)); Issue.record("must not decode") } catch let e as MarginError { #expect(e.code == "invalid") }
            // The raw bytes can be read, and a write with the right version replaces them only on purpose.
            #expect(try await store.readData(vp(path)).data == bytes)
            #expect(v.dir.bytes(path) == bytes)
            let listed = try await v.env.notes.notes(course: nil).map(\.title)
            #expect(!listed.contains { $0.contains("Caf") }, "a latin-1 file must not be listed")
            #expect(await robustCode { try await v.env.notes.open(id: "\(Self.folder)/Corrupt 3 latin-1 bytes") } == "notFound")
        }
    }

    // MARK: Writing next to corrupt files, and into them

    @Test func editsKeepEverythingTheyDidNotTouch() async throws {
        try await withRobustVault(seed: Self.seed) { v in
            let known = Set(try await v.env.notes.notes(course: nil).map(\.id))
            var corrupt: [(id: String, path: String)] = []
            var claimed = Set<String>()   // two files with one id: the service edits the one the index holds
            for (i, sample) in Self.corpus.enumerated() where sample.utf8 {
                let path = "\(Self.folder)/Corrupt \(i) \(sample.name).md"
                let derived = String(path.dropLast(3))
                let declared = String(decoding: sample.bytes.prefix(400), as: UTF8.self).components(separatedBy: "\n")
                    .first { $0.hasPrefix("id: ") }.map { String($0.dropFirst(4)) }
                if known.contains(derived) { corrupt.append((derived, path)) }
                else if let declared, known.contains(declared), claimed.insert(declared).inserted { corrupt.append((declared, path)) }
            }
            #expect(corrupt.count >= 10, "only \(corrupt.count) corpus notes are indexed")
            var edited = 0
            for note in corrupt {
                let path = note.path
                guard let original = v.dir.bytes(path) else { continue }
                guard let opened = try? await v.env.notes.open(id: note.id) else { continue }
                // Saving what was read changes nothing.
                let same = await robustCode { try await v.env.notes.save(id: note.id, text: opened.text, actor: robustActor, baseVersion: opened.version, dryRun: false, idempotencyKey: nil) }
                #expect(same == nil || same == "invalid", "\(path): \(same ?? "")")
                #expect(v.dir.bytes(path) == original, "\(path): saving the unchanged text changed the file")
                // Appending keeps the frontmatter and the old body exactly.
                let appended = await robustCode { try await v.env.notes.save(id: note.id, text: opened.text + "\nappended line\n", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
                if appended == nil {
                    edited += 1
                    let after = try #require(v.dir.bytes(path))
                    let bodyStart = original.count - Data(opened.text.utf8).count
                    if bodyStart >= 0 {
                        #expect(after.prefix(bodyStart) == original.prefix(bodyStart), "\(path): frontmatter bytes changed by a body edit")
                    }
                    #expect(String(decoding: after, as: UTF8.self).contains("appended line"), "\(path)")
                } else {
                    #expect(appended == "invalid", "\(path): \(appended ?? "")")
                    #expect(v.dir.bytes(path) == original, "\(path): a refused edit changed the file")
                }
                // A property edit either works and keeps the body, or is refused and leaves the file alone.
                let before = v.dir.bytes(path) ?? original
                let set = await robustCode { try await v.env.properties.set(key: "difficulty", value: .number(4), on: note.id, actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
                if set == nil {
                    let after = String(decoding: try #require(v.dir.bytes(path)), as: UTF8.self)
                    #expect(after.contains(opened.text) || after.contains("appended line"), "\(path): the body was lost by a property edit")
                } else {
                    #expect(set == "invalid", "\(path): \(set ?? "")")
                    #expect(v.dir.bytes(path) == before, "\(path): a refused property edit changed the file")
                }
            }
            #expect(edited > 5, "only \(edited) corrupt notes could be edited")
            #expect(v.dir.temporaryFiles.isEmpty)
            #expect(await v.matchesRestart())
        }
    }

    @Test func taskTogglesInCorruptNotesFlipOneCharacterOrAreRefused() async throws {
        try await withRobustVault(seed: Self.seed) { v in
            let tasks = try await v.env.tasks.tasks(course: "bio").filter { $0.id.hasPrefix("t-") || $0.id.hasPrefix("^t-") || $0.id.contains("-") }
            var toggled = 0
            for task in tasks where Self.corpusTaskIDs.contains(task.id) {
                let before = v.files()
                let code = await robustCode { try await v.env.tasks.toggle(id: task.id, actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
                let after = v.files()
                if code == nil {
                    toggled += 1
                    let changed = after.filter { before[$0.key] != $0.value }
                    #expect(changed.count == 1, "\(task.id): \(changed.keys)")
                    if let (path, data) = changed.first, let old = before[path] {
                        let diff = zip(old, data).filter { $0 != $1 }.count
                        #expect(old.count == data.count && diff == 1, "\(task.id): \(diff) bytes differ, sizes \(old.count) -> \(data.count)")
                    }
                } else {
                    #expect(["notFound", "invalid", "conflict"].contains(code ?? ""), "\(task.id): \(code ?? "")")
                    #expect(after == before, "\(task.id): a refused toggle changed the vault")
                }
            }
            #expect(toggled >= 3, "only \(toggled) toggles worked")
        }
    }

    static let corpusTaskIDs: Set<String> = ["t-bad1", "t-unt1", "t-nul1", "t-lng1", "t-crl1", "t-cr01", "t-dup1"]

    // MARK: Corruption while the app runs

    @Test(arguments: corpus.filter { !$0.utf8 || $0.name == "nul bytes in the body" || $0.name == "empty file" || $0.name == "malformed yaml" })
    func aNoteThatIsCorruptedFromOutsideStaysSafeAndRecovers(sample: Sample) async throws {
        try await withRobustVault { v in
            let path = try #require(v.dir.path(ofNoteWithID: "bio/lecture-8"))
            let original = try #require(v.dir.bytes(path))
            _ = try await v.env.notes.open(id: "bio/lecture-8")
            let updates = v.env.notes.externalChanges
            _ = updates
            // Another program overwrites the note, then drops a marker note so we know the scan ran.
            try sample.bytes.write(to: v.dir.file(path))
            try v.dir.seed("\(Self.folder)/Marker \(sample.name).md", Data("---\nid: bio/marker\n---\n# Marker\n".utf8))
            let seen = await eventually { (try? await v.env.notes.open(id: "bio/marker")) != nil }
            #expect(seen, "the watcher never reported the marker")
            await exerciseReads(v.env)
            // Whatever the index made of it, the service answers with a typed error or the text, and never writes.
            let open = await robustCode { try await v.env.notes.open(id: "bio/lecture-8") }
            #expect(open == nil || open == "invalid" || open == "notFound", "\(open ?? "")")
            let save = await robustCode { try await v.env.notes.save(id: "bio/lecture-8", text: "overwrite attempt", actor: robustActor, baseVersion: "0000", dryRun: false, idempotencyKey: nil) }
            #expect(save == "conflict" || save == "invalid" || save == "notFound", "\(save ?? "")")
            #expect(v.dir.bytes(path) == sample.bytes, "the corrupt file was changed by a service")
            // The user repairs the file: everything works again.
            try original.write(to: v.dir.file(path))
            let repaired = await eventually { (try? await v.env.notes.open(id: "bio/lecture-8"))?.text.hasPrefix("# Lecture 8") == true }
            #expect(repaired, "the note did not recover after it was repaired")
            #expect(await robustCode { try await v.env.notes.save(id: "bio/lecture-8", text: "# Lecture 8\n\nfine again\n", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == nil)
        }
    }

    // MARK: Course files and app data

    static let corruptCourseFiles: [Sample] = [
        Sample(name: "malformed yaml", bytes: Data("---\nid: [unclosed\nname: : :\n---\n".utf8), utf8: true),
        Sample(name: "binary", bytes: Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81]), utf8: false),
        Sample(name: "nul bytes", bytes: Data("---\nid: chem\0\nname: Chem\0istry\n---\n".utf8), utf8: true),
        Sample(name: "empty", bytes: Data(), utf8: true),
        Sample(name: "no frontmatter", bytes: Data("just text, no frontmatter\n".utf8), utf8: true),
    ]

    @Test(arguments: corruptCourseFiles)
    func aCorruptCourseFileNeverStopsTheRest(sample: Sample) async throws {
        try await withRobustVault(seed: { dir in
            let path = try #require(dir.path(ofNoteWithID: "chem").flatMap { $0.hasSuffix("_course.md") ? $0 : nil } ?? dir.snapshot().keys.first { $0.contains("Chemistry") && $0.hasSuffix("_course.md") })
            try sample.bytes.write(to: dir.file(path))
        }) { v in
            await exerciseReads(v.env)
            let courses = try await v.env.courses.courses(query: nil).map(\.id)
            #expect(courses.contains("bio") && courses.contains("math"), "the other courses must survive: \(courses)")
            _ = try await v.env.courses.sessions(week: 5)
            // Working in another course is unaffected; the corrupt file is never rewritten.
            let path = try #require(v.dir.snapshot().keys.first { $0.contains("Chemistry") && $0.hasSuffix("_course.md") })
            let before = v.dir.bytes(path)
            #expect(await robustCode { try await v.env.notes.save(id: "bio/lecture-8", text: "# ok\n", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) } == nil)
            let style = await robustCode { try await v.env.courseWriter.setStyle(id: "chem", icon: "science", color: "econ", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
            if style != nil { #expect(["notFound", "invalid", "io"].contains(style ?? ""), "\(style ?? "")") }
            if style != nil { #expect(v.dir.bytes(path) == before, "a refused edit changed the corrupt course file") }
            #expect(v.dir.temporaryFiles.isEmpty)
        }
    }

    static let corruptSemesters: [Sample] = [
        Sample(name: "garbage", bytes: Data("{ this is not json".utf8), utf8: true),
        Sample(name: "binary", bytes: Data([0xFF, 0xFE, 0x00, 0x80]), utf8: false),
        Sample(name: "empty", bytes: Data(), utf8: true),
        Sample(name: "wrong shape", bytes: Data("{\"semesters\": 3}".utf8), utf8: true),
        Sample(name: "nul", bytes: Data("[\0]".utf8), utf8: true),
    ]

    @Test(arguments: corruptSemesters)
    func aCorruptSemestersFileFallsBackAndIsNeverOverwritten(sample: Sample) async throws {
        try await withRobustVault(seed: { dir in try dir.seed(".margin/semesters.json", sample.bytes) }) { v in
            await exerciseReads(v.env)
            let semesters = try await v.env.courses.semesters()
            let courses = try await v.env.courses.courses(query: nil)
            #expect(!semesters.isEmpty, "the semesters must come from the course folders")
            #expect(!courses.isEmpty)
            let code = await robustCode { try await v.env.courseWriter.setArchived(semester: "fall-2026", true, actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
            if !sample.bytes.isEmpty { #expect(code != nil && code != "other", "archiving over a corrupt semesters.json: \(code ?? "succeeded")") }
            if !sample.bytes.isEmpty { #expect(v.dir.bytes(".margin/semesters.json") == sample.bytes, "the corrupt semesters.json was overwritten") }
            if !sample.bytes.isEmpty { #expect(v.dir.exists("Fall 2026"), "the semester folder must not move when the flag could not be written") }
        }
    }
}

/// Hostile titles and text handed to the services (an agent or a paste can send anything).
@Suite struct HostileInputTests {
    static let titles: [String] = [
        String(repeating: "a", count: 300), String(repeating: "🧬", count: 100), "a\0b", "../../escape", "..", ".", "/", "x/y",
        ".hidden", "   ", "CON", "nul.md", "trailing dot.", "line\nbreak", "\u{202E}rtl", String(repeating: "é", count: 200),
    ]

    @Test(arguments: titles)
    func aStrangeTitleIsRefusedOrStoredInsideTheCourseFolder(title: String) async throws {
        try await withRobustVault { v in
            let parent = v.dir.url.deletingLastPathComponent()
            let before = v.files()
            let code = await robustCode { try await v.env.notes.create(course: "bio", title: title, kind: .note, text: "body \0 text", actor: robustActor, baseVersion: nil, dryRun: false, idempotencyKey: nil) }
            #expect(code == nil || ["invalid", "conflict", "io"].contains(code ?? ""), "\(code ?? "")")
            let escaped = ((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []).filter { $0.hasPrefix("escape") }
            #expect(escaped.isEmpty, "a title walked out of the vault: \(escaped)")
            let added = v.files().keys.filter { before[$0] == nil }
            #expect(added.allSatisfy { $0.hasPrefix("Fall 2026/Cell Biology/") }, "\(added)")
            #expect(code != nil || added.count == 1, "\(added)")
            // Capture with the same text goes to the inbox or a course, never elsewhere.
            let cap = await robustCode { try await v.env.capture.commit(CaptureDraft(text: title, kind: .note), actor: robustActor, dryRun: false, idempotencyKey: nil) }
            #expect(cap == nil || ["invalid", "io"].contains(cap ?? ""), "\(cap ?? "")")
            let capAdded = v.files().keys.filter { before[$0] == nil && !added.contains($0) }
            #expect(capAdded.allSatisfy { $0.hasPrefix("_inbox/") }, "\(capAdded)")
            await exerciseReads(v.env)
            #expect(await v.matchesRestart())
        }
    }
}
