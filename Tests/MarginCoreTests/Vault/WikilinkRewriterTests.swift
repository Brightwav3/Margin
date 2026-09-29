import Foundation
import Testing
@testable import MarginCore

@Suite struct WikilinkRewriterTests {
    /// Opens a vault seeded with `files` and a rewriter attached.
    private func vault(_ files: [String: String], rewriter: WikilinkRewriter = WikilinkRewriter()) async throws -> (TempDir, VaultStore, WikilinkRewriter) {
        let dir = TempDir()
        for (path, text) in files { try dir.seed(path, Data(text.utf8)) }
        let store = try await VaultStore.open(root: dir.url, trash: PortableTrash())
        await store.addRenameObserver(rewriter)
        return (dir, store, rewriter)
    }

    private func text(_ dir: TempDir, _ path: String) -> String {
        dir.bytes(path).map { String(decoding: $0, as: UTF8.self) } ?? "<missing>"
    }

    @Test func rewritesPlainLinkAndIgnoresOthers() async throws {
        let (dir, store, rewriter) = try await vault([
            "Bio/Old.md": "# Old\n",
            "Bio/Other.md": "keep",
            "Bio/x.md": "See [[Old]] and [[Other]] and [[Missing]].\n",
        ])
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        #expect(text(dir, "Bio/x.md") == "See [[New]] and [[Other]] and [[Missing]].\n")
        #expect(text(dir, "Bio/Other.md") == "keep")
        let report = await rewriter.lastReport
        #expect(report.notesRewritten == [vp("Bio/x.md")])
        #expect(report.linksRewritten == 1)
        #expect(report.failed.isEmpty)
    }

    @Test func keepsAliasHeadingAndBlockID() async throws {
        let (dir, store, _) = try await vault([
            "Bio/Old.md": "",
            "Bio/x.md": "[[Old|the alias]] [[Old#Intro]] [[Old#Intro|alias]] [[Old#^abc123]] [[Old #Spaced | al ]]\n",
        ])
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        #expect(text(dir, "Bio/x.md") == "[[New|the alias]] [[New#Intro]] [[New#Intro|alias]] [[New#^abc123]] [[New #Spaced | al ]]\n")
    }

    @Test func rewritesEmbedsAndKeepsSizeAlias() async throws {
        let (dir, store, _) = try await vault([
            "Bio/Old.md": "",
            "Bio/x.md": "![[Old]] and ![[Old|200]] and ![[Old#H]]\n",
        ])
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        #expect(text(dir, "Bio/x.md") == "![[New]] and ![[New|200]] and ![[New#H]]\n")
    }

    @Test func folderFormKeepsFolder() async throws {
        let (dir, store, _) = try await vault([
            "Bio/Cell Biology/Glossary.md": "",
            "Chem/Glossary.md": "",
            "Chem/x.md": "[[Cell Biology/Glossary]] [[Bio/Cell Biology/Glossary|g]] [[Glossary]]\n",
        ])
        try await store.rename(vp("Bio/Cell Biology/Glossary.md"), to: vp("Bio/Cell Biology/Terms.md"))
        // The bare `[[Glossary]]` resolves to Chem's own note and must not change.
        #expect(text(dir, "Chem/x.md") == "[[Cell Biology/Terms]] [[Bio/Cell Biology/Terms|g]] [[Glossary]]\n")
    }

    @Test func caseInsensitiveMatchAndMdSuffixKept() async throws {
        let (dir, store, _) = try await vault([
            "Bio/Old.md": "",
            "Bio/x.md": "[[old]] [[Old.md]] [[ OLD ]]\n",
        ])
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        #expect(text(dir, "Bio/x.md") == "[[New]] [[New.md]] [[ New ]]\n")
    }

    @Test func codeBlocksAndInlineCodeAreUntouched() async throws {
        let source = """
        [[Old]] real
        ```
        [[Old]] in fence
        ```
        `[[Old]]` inline
        ~~~md
        ![[Old]]
        ~~~
        [[Old|kept]] again

        """
        let (dir, store, _) = try await vault(["Bio/Old.md": "", "Bio/x.md": source])
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        let expected = source
            .replacingOccurrences(of: "[[Old]] real", with: "[[New]] real")
            .replacingOccurrences(of: "[[Old|kept]]", with: "[[New|kept]]")
        #expect(text(dir, "Bio/x.md") == expected)
    }

    @Test func everythingElseStaysByteIdentical() async throws {
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("---\r\nclass: \"[[Old]]\"\r\n---\r\nPříliš [[Old]] žluťoučký\tkůň 🧬\r\n- [ ] task ^t-1\r\n\r\ntrailing  ".utf8)
        let dir = TempDir()
        try dir.seed("Bio/Old.md", Data())
        try dir.seed("Bio/x.md", bytes)
        let store = try await VaultStore.open(root: dir.url, trash: PortableTrash())
        await store.addRenameObserver(WikilinkRewriter())
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        let actual = try #require(dir.bytes("Bio/x.md"))
        // Only the body link changed; the frontmatter value, BOM, CRLF and spacing are as before.
        var want = bytes
        let body = want.range(of: Data("Příliš [[Old]]".utf8))!
        want.replaceSubrange(body, with: Data("Příliš [[New]]".utf8))
        #expect(actual == want)
    }

    @Test func ambiguousNewNameUsesFolderForm() async throws {
        let (dir, store, _) = try await vault([
            "A/Old.md": "",
            "B/New.md": "",
            "C/x.md": "[[Old]] [[Old|alias]]\n",
            "A/y.md": "[[Old]]\n",
        ])
        try await store.rename(vp("A/Old.md"), to: vp("A/New.md"))
        // From C both notes are equally good; the folder form disambiguates.
        #expect(text(dir, "C/x.md") == "[[A/New]] [[A/New|alias]]\n")
        // From the same course the bare name still resolves uniquely.
        #expect(text(dir, "A/y.md") == "[[New]]\n")
    }

    @Test func moveWithoutRenameOnlyChangesLinksThatBecomeAmbiguous() async throws {
        let (dir, store, _) = try await vault([
            "A/Glossary.md": "",
            "B/Glossary.md": "",
            "Docs/Note.md": "",
            "C/x.md": "[[Note]] [[Glossary]]\n",
        ])
        // `Note` keeps its name and stays unique: no rewrite. `Glossary` was already ambiguous: untouched.
        try await store.rename(vp("Docs/Note.md"), to: vp("Other/Note.md"))
        #expect(text(dir, "C/x.md") == "[[Note]] [[Glossary]]\n")
        // Moving into a folder that makes the name clash forces the shortest unique folder form.
        try await store.rename(vp("Other/Note.md"), to: vp("A/Sub/Glossary.md"))
        #expect(text(dir, "C/x.md") == "[[Sub/Glossary]] [[Glossary]]\n")
    }

    @Test func linksThatWereAmbiguousBeforeAreLeftAlone() async throws {
        let (dir, store, _) = try await vault([
            "A/Old.md": "", "B/Old.md": "", "C/x.md": "[[Old]]\n",
        ])
        try await store.rename(vp("A/Old.md"), to: vp("A/New.md"))
        #expect(text(dir, "C/x.md") == "[[Old]]\n")
    }

    @Test func sameCoursePreferenceDecidesWhichLinksFollow() async throws {
        let (dir, store, _) = try await vault([
            "Bio/Glossary.md": "", "Chem/Glossary.md": "",
            "Bio/x.md": "[[Glossary]]\n", "Chem/y.md": "[[Glossary]]\n",
        ])
        try await store.rename(vp("Bio/Glossary.md"), to: vp("Bio/Terms.md"))
        #expect(text(dir, "Bio/x.md") == "[[Terms]]\n")
        #expect(text(dir, "Chem/y.md") == "[[Glossary]]\n")
    }

    @Test func folderRenameRewritesFolderLinksAndLeavesBareOnes() async throws {
        let (dir, store, rewriter) = try await vault([
            "Bio/Glossary.md": "links [[Osmosis]] and [[Bio/Osmosis]]\n",
            "Bio/Osmosis.md": "back to [[Glossary]]\n",
            "Chem/x.md": "[[Bio/Glossary]] [[Glossary]] [[Bio/Osmosis|o]] ![[Bio/Osmosis]]\n",
        ])
        try await store.rename(vp("Bio"), to: vp("Biology"))
        #expect(text(dir, "Chem/x.md") == "[[Biology/Glossary]] [[Glossary]] [[Biology/Osmosis|o]] ![[Biology/Osmosis]]\n")
        #expect(text(dir, "Biology/Glossary.md") == "links [[Osmosis]] and [[Biology/Osmosis]]\n")
        #expect(text(dir, "Biology/Osmosis.md") == "back to [[Glossary]]\n")
        #expect(await rewriter.lastReport.failed.isEmpty)
    }

    @Test func renamedNoteRewritesItsOwnLinkToItself() async throws {
        let (dir, store, _) = try await vault([
            "Bio/Old.md": "self [[Old]] and [[#Heading]] and [[Old#Heading]]\n",
        ])
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        #expect(text(dir, "Bio/New.md") == "self [[New]] and [[#Heading]] and [[New#Heading]]\n")
    }

    @Test func disabledRewriterAndNonMarkdownRenamesChangeNothing() async throws {
        let (dir, store, rewriter) = try await vault(
            ["Bio/Old.md": "", "Bio/pic.png": "png", "Bio/x.md": "[[Old]] ![[pic.png]]\n"],
            rewriter: WikilinkRewriter(isEnabled: false))
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        #expect(text(dir, "Bio/x.md") == "[[Old]] ![[pic.png]]\n")
        #expect(await rewriter.lastReport == WikilinkRewriter.Report())

        let (dir2, store2, rewriter2) = try await vault(["Bio/Old.md": "", "Bio/pic.png": "png", "Bio/x.md": "[[Old]] ![[pic.png]]\n"])
        try await store2.rename(vp("Bio/pic.png"), to: vp("Bio/pic2.png"))
        #expect(text(dir2, "Bio/x.md") == "[[Old]] ![[pic.png]]\n")
        #expect(await rewriter2.lastReport == WikilinkRewriter.Report())
    }

    @Test func rewritesEveryOccurrenceAcrossManyNotes() async throws {
        var files = ["Bio/Old.md": ""]
        for i in 0..<25 { files["Bio/n\(i).md"] = "a [[Old]] b [[Old|x]]\n[[Old#h]]\n" }
        let (dir, store, rewriter) = try await vault(files)
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        for i in 0..<25 { #expect(text(dir, "Bio/n\(i).md") == "a [[New]] b [[New|x]]\n[[New#h]]\n") }
        #expect(await rewriter.lastReport.linksRewritten == 75)
    }

    @Test func rewriteWritesAtomicallyWithoutLeavingTemporaryFiles() async throws {
        let (dir, store, _) = try await vault(["Bio/Old.md": "", "Bio/x.md": "[[Old]]\n"])
        try await store.rename(vp("Bio/Old.md"), to: vp("Bio/New.md"))
        #expect(dir.temporaryFiles.isEmpty)
    }
}
