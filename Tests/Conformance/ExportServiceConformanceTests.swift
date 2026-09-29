import Foundation
import Testing
@testable import MarginCore

private func codeOf<T>(_ body: () async throws -> T) async -> String? {
    do { _ = try await body(); return nil } catch let e as MarginError { return e.code } catch { return "other" }
}

private let body = """
    # Export Test

    See [[Glossary]] and [[Glossary|the terms]] and [[Glossary#Enzymes]], also [[Other Note]].
    Unknown: [[Not There Yet]]. Self: [[#Details]].
    ![[membrane.png]] and ![[Glossary]]

    `[[in code]]` stays.

    ```
    [[Glossary]]
    ```

    A [normal link](https://example.com) and - [ ] a task ^t-abc123

    ## Details

    """

/// `ExportService`, run against both environments (contract §5).
@Suite struct ExportServiceConformanceTests {
    private func makeNotes(_ h: Harness) async throws {
        _ = try await h.notes.create(course: "hist", title: "Other Note", kind: .note, text: "# Other Note\n", actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        _ = try await h.notes.create(course: "bio", title: "Export Test", kind: .note, text: body, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
    }

    @Test(arguments: HarnessKind.allCases)
    func markdownWithPlainTextLinks(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            try await makeNotes(h)
            let file = try await h.exporter.export(note: "bio/export-test", format: .markdown)
            #expect(file.fileName == "Export Test.md" && file.format == .markdown)
            let text = file.text ?? ""
            #expect(text == """
                # Export Test

                See Glossary and the terms and Glossary > Enzymes, also Other Note.
                Unknown: Not There Yet. Self: Details.
                ![membrane.png](_files/membrane.png) and Glossary

                `[[in code]]` stays.

                ```
                [[Glossary]]
                ```

                A [normal link](https://example.com) and - [ ] a task ^t-abc123

                ## Details

                """)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func markdownWithRelativeLinks(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            try await makeNotes(h)
            let file = try await h.exporter.export(note: "bio/export-test", format: .markdown,
                                                   options: ExportOptions(includeFrontmatter: false, wikilinks: .relativeLinks))
            let lines = (file.text ?? "").components(separatedBy: "\n")
            #expect(lines[2] == "See [Glossary](Glossary.md) and [the terms](Glossary.md) and [Glossary](Glossary.md#enzymes), also [Other Note](../Modern%20Europe/Other%20Note.md).")
            #expect(lines[3] == "Unknown: Not There Yet. Self: [Details](#details).")
            #expect(lines[4] == "![membrane.png](_files/membrane.png) and [Glossary](Glossary.md)")
            #expect(lines[6] == "`[[in code]]` stays." && lines[9] == "[[Glossary]]")
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func frontmatterIsOptional(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let without = try await h.exporter.export(note: "bio/lecture-9", format: .markdown).text ?? ""
            #expect(!without.hasPrefix("---") && without.hasPrefix("#"))
            let with = try await h.exporter.export(note: "bio/lecture-9", format: .markdown, options: ExportOptions(includeFrontmatter: true)).text ?? ""
            #expect(with.hasPrefix("---\n") && with.contains("id: bio/lecture-9") && with.hasSuffix(without))
            #expect(with.contains("type: lecture"))
            let raw = try await h.rawContent("bio/lecture-9")
            let noLinks = raw.contains("[[") ? nil : raw
            if let noLinks { #expect(with == noLinks) }
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func exportChangesNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let before = try await h.notes.open(id: "bio/lecture-9").version
            _ = try await h.exporter.export(note: "bio/lecture-9", format: .markdown)
            #expect(try await h.notes.open(id: "bio/lecture-9").version == before)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func pdfAndUnknownNotes(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            #expect(await codeOf { try await h.exporter.export(note: "nope/none", format: .markdown) } == "notFound")
            #expect(await codeOf { try await h.exporter.export(note: "nope/none", format: .pdf) } == "notFound")
            #if !os(macOS)
            do {
                _ = try await h.exporter.export(note: "bio/lecture-9", format: .pdf)
                Issue.record("PDF export must not work without a renderer")
            } catch let e as MarginError {
                #expect(e == .invalid("PDF export requires macOS"))
            }
            #endif
        }
    }
}
