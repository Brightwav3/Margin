import Foundation
import Testing
@testable import MarginCore

/// One suite, run against `FixturePropertyService` and `VaultPropertyService` (contract §5).
@Suite struct PropertyServiceConformanceTests {
    let note = "bio/lecture-8"

    /// The frontmatter lines (between the fences) and everything after the closing fence.
    private func split(_ content: String) -> (lines: [String], rest: String) {
        let parts = content.components(separatedBy: "\n---\n")
        #expect(parts.count >= 2 && parts[0].hasPrefix("---"))
        let lines = parts[0].split(separator: "\n", omittingEmptySubsequences: false).dropFirst().map(String.init)
        return (lines, parts.dropFirst().joined(separator: "\n---\n"))
    }

    // MARK: Lossless writes

    @Test(arguments: HarnessKind.allCases)
    func newKeyIsAppendedAndEverythingElseIsUntouched(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.rawContent(note)
            let cs = try await h.properties.set(key: "difficulty", value: .number(3), on: note, actor: testActor,
                                                baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let after = try await h.rawContent(note)
            let (a, b) = (split(before), split(after))
            #expect(b.lines == a.lines + ["difficulty: 3"])
            #expect(b.rest == a.rest)
            #expect(cs.entries.count == 1 && cs.entries[0].kind == .modified && cs.entries[0].noteID == note)
            #expect(cs.actor == testActor && !cs.isDryRun)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func existingKeyKeepsItsPosition(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = split(try await h.rawContent(note))
            let index = try #require(before.lines.firstIndex { $0.hasPrefix("type:") })
            _ = try await h.properties.set(key: "type", value: .string("lab"), on: note, actor: .user,
                                           baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let after = split(try await h.rawContent(note))
            #expect(after.lines.count == before.lines.count)
            #expect(after.lines[index] == "type: lab")
            var expected = before.lines
            expected[index] = "type: lab"
            #expect(after.lines == expected)
            #expect(after.rest == before.rest)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func unknownKeysSurviveOtherEdits(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            for (key, value) in [("mood", FrontmatterValue.string("calm")), ("rating", .number(4))] {
                _ = try await h.properties.set(key: key, value: value, on: note, actor: .user, baseVersion: nil,
                                               dryRun: false, idempotencyKey: nil)
            }
            _ = try await h.properties.set(key: "type", value: .string("seminar"), on: note, actor: .user,
                                           baseVersion: nil, dryRun: false, idempotencyKey: nil)
            _ = try await h.properties.remove(key: "date", on: note, actor: .user, baseVersion: nil, dryRun: false,
                                              idempotencyKey: nil)
            let lines = split(try await h.rawContent(note)).lines
            #expect(lines == ["id: bio/lecture-8", "class: \"[[Cell Biology]]\"", "type: seminar", "mood: calm", "rating: 4"]
                    || lines == ["id: \"bio/lecture-8\"", "class: \"[[Cell Biology]]\"", "type: seminar", "mood: calm", "rating: 4"],
                    "\(lines)")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func bodyAndNoteTextDoNotChange(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: note)
            _ = try await h.properties.set(key: "difficulty", value: .number(2), on: note, actor: .user,
                                           baseVersion: before.version, dryRun: false, idempotencyKey: nil)
            let after = try await h.notes.open(id: note)
            #expect(after.text == before.text)
            #expect(after.version != before.version)
        }
    }

    // MARK: Types and validation

    @Test(arguments: HarnessKind.allCases)
    func typesListBuiltInAndInferredKeys(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            var types = try await h.properties.types()
            #expect(types["date"] == .date && types["due"] == .date && types["tags"] == .tags)
            #expect(types["class"] == .link && types["weight"] == .number && types["type"] == .text)
            #expect(types["difficulty"] == nil)
            _ = try await h.properties.set(key: "Difficulty", value: .number(3), on: note, actor: .user,
                                           baseVersion: nil, dryRun: false, idempotencyKey: nil)
            types = try await h.properties.types()
            #expect(types["difficulty"] == .number)
            // The inferred type now guards the key.
            await #expect(throws: MarginError.self) {
                try await h.properties.set(key: "difficulty", value: .string("hard"), on: note, actor: .user,
                                           baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func valuesAreStoredInCanonicalForm(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            func set(_ key: String, _ value: FrontmatterValue) async throws {
                _ = try await h.properties.set(key: key, value: value, on: note, actor: .user, baseVersion: nil,
                                               dryRun: false, idempotencyKey: nil)
            }
            try await set("tags", .string("#exam, exam study"))
            try await set("weight", .string("25"))
            try await set("due", .string("2026-10-01"))
            try await set("class", .string("Cell Biology"))
            let (fm, _) = Frontmatter.parse(try await h.rawContent(note))
            let front = try #require(fm)
            #expect(front.value(for: "tags") == .list(["exam", "study"]))
            #expect(front.value(for: "weight") == .number(25))
            #expect(front.value(for: "due") == .date(.literal(2026, 10, 1)))
            #expect(front.value(for: "class") == .string("[[Cell Biology]]"))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func invalidInputsThrowInvalidAndChangeNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.rawContent(note)
            let bad: [(String, FrontmatterValue)] = [
                ("date", .string("not a date")), ("weight", .string("heavy")), ("tags", .number(3)),
                ("due", .null), ("", .string("x")), ("a:b", .string("x")), ("id", .string("hijack")),
            ]
            for (key, value) in bad {
                do {
                    _ = try await h.properties.set(key: key, value: value, on: note, actor: .user, baseVersion: nil,
                                                   dryRun: false, idempotencyKey: nil)
                    Issue.record("expected .invalid for \(key)")
                } catch let error as MarginError {
                    if case .invalid = error {} else { Issue.record("\(key): \(error)") }
                }
            }
            do {
                _ = try await h.properties.remove(key: "id", on: note, actor: .user, baseVersion: nil, dryRun: false,
                                                  idempotencyKey: nil)
                Issue.record("id must not be removable")
            } catch let error as MarginError {
                if case .invalid = error {} else { Issue.record("\(error)") }
            }
            #expect(try await h.rawContent(note) == before)
        }
    }

    // MARK: Remove, no-ops, errors

    @Test(arguments: HarnessKind.allCases)
    func removeDropsOnlyThatKey(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = split(try await h.rawContent(note))
            let cs = try await h.properties.remove(key: "type", on: note, actor: .user, baseVersion: nil, dryRun: false,
                                                   idempotencyKey: nil)
            #expect(cs.entries.count == 1)
            let after = split(try await h.rawContent(note))
            #expect(after.lines == before.lines.filter { !$0.hasPrefix("type:") })
            #expect(after.rest == before.rest)
            // Removing again, or removing an absent key, changes nothing.
            let again = try await h.properties.remove(key: "type", on: note, actor: .user, baseVersion: nil,
                                                      dryRun: false, idempotencyKey: nil)
            #expect(again.isEmpty)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func settingTheSameValueIsAnEmptyChangeSet(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: note)
            let cs = try await h.properties.set(key: "type", value: .string("lecture"), on: note, actor: .user,
                                                baseVersion: before.version, dryRun: false, idempotencyKey: nil)
            #expect(cs.isEmpty)
            #expect(try await h.notes.open(id: note).version == before.version)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func unknownNoteIsNotFound(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            do {
                _ = try await h.properties.set(key: "x", value: .string("y"), on: "bio/nope", actor: .user,
                                               baseVersion: nil, dryRun: false, idempotencyKey: nil)
                Issue.record("expected notFound")
            } catch let error as MarginError {
                if case .notFound = error {} else { Issue.record("\(error)") }
            }
        }
    }

    // MARK: Write context (contract rule 0)

    @Test(arguments: HarnessKind.allCases)
    func staleBaseVersionConflictsAndChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let old = try await h.notes.open(id: note)
            _ = try await h.properties.set(key: "difficulty", value: .number(1), on: note, actor: .user,
                                           baseVersion: old.version, dryRun: false, idempotencyKey: nil)
            let mid = try await h.rawContent(note)
            do {
                _ = try await h.properties.set(key: "difficulty", value: .number(2), on: note, actor: testActor,
                                               baseVersion: old.version, dryRun: false, idempotencyKey: nil)
                Issue.record("expected conflict")
            } catch let error as MarginError {
                if case .conflict = error {} else { Issue.record("\(error)") }
            }
            #expect(try await h.rawContent(note) == mid)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func dryRunReportsTheChangeAndWritesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: note)
            let raw = try await h.rawContent(note)
            let cs = try await h.properties.set(key: "difficulty", value: .number(5), on: note, actor: testActor,
                                                baseVersion: before.version, dryRun: true, idempotencyKey: "k-dry")
            #expect(cs.isDryRun && cs.entries.count == 1)
            #expect(cs.entries[0].beforeHash == before.version)
            #expect(try await h.rawContent(note) == raw)
            #expect(try await h.notes.open(id: note).version == before.version)
            // A dry run does not consume the idempotency key.
            let real = try await h.properties.set(key: "difficulty", value: .number(5), on: note, actor: testActor,
                                                  baseVersion: before.version, dryRun: false, idempotencyKey: "k-dry")
            #expect(!real.isDryRun && real.entries.count == 1)
            // The dry run predicted the real hash.
            #expect(real.entries[0].afterHash == cs.entries[0].afterHash)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func changeSetHashesMatchTheNoteVersions(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: note)
            let cs = try await h.properties.set(key: "difficulty", value: .number(4), on: note, actor: .user,
                                                baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let after = try await h.notes.open(id: note)
            #expect(cs.entries[0].beforeHash == before.version)
            #expect(cs.entries[0].afterHash == after.version)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func repeatedIdempotencyKeyReturnsTheFirstResult(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let first = try await h.properties.set(key: "difficulty", value: .number(1), on: note, actor: testActor,
                                                   baseVersion: nil, dryRun: false, idempotencyKey: "k-1")
            let second = try await h.properties.set(key: "difficulty", value: .number(9), on: note, actor: testActor,
                                                    baseVersion: nil, dryRun: false, idempotencyKey: "k-1")
            #expect(second == first)
            let lines = split(try await h.rawContent(note)).lines
            #expect(lines.last == "difficulty: 1")
        }
    }
}
