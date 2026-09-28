import Testing
@testable import MarginCore

@Suite struct WikilinkExtractorTests {
    struct Case: Sendable {
        var input: String
        var target: String
        var heading: String? = nil
        var blockID: String? = nil
        var alias: String? = nil
        var embed = false
    }

    // 25 parsing cases: each input holds exactly one link.
    static let cases: [Case] = [
        Case(input: "[[Note]]", target: "Note"),
        Case(input: "see [[Note]] here", target: "Note"),
        Case(input: "[[Note|alias]]", target: "Note", alias: "alias"),
        Case(input: "[[ Note | spaced alias ]]", target: "Note", alias: "spaced alias"),
        Case(input: "[[Note#Heading]]", target: "Note", heading: "Heading"),
        Case(input: "[[Note#Two Words]]", target: "Note", heading: "Two Words"),
        Case(input: "[[Note#Heading|alias]]", target: "Note", heading: "Heading", alias: "alias"),
        Case(input: "[[Note#^abc123]]", target: "Note", blockID: "abc123"),
        Case(input: "[[#Local heading]]", target: "", heading: "Local heading"),
        Case(input: "[[Cell Biology/Glossary]]", target: "Cell Biology/Glossary"),
        Case(input: "[[bio/Cell Biology/Glossary#Terms|t]]", target: "bio/Cell Biology/Glossary", heading: "Terms", alias: "t"),
        Case(input: "![[Diagram.png]]", target: "Diagram.png", embed: true),
        Case(input: "![[Diagram.png|200]]", target: "Diagram.png", alias: "200", embed: true),
        Case(input: "![[Note#Heading]]", target: "Note", heading: "Heading", embed: true),
        Case(input: "[[Note.md]]", target: "Note"),
        Case(input: "[[Ústřední dogma]]", target: "Ústřední dogma"),
        Case(input: "[[Note with (parens)]]", target: "Note with (parens)"),
        Case(input: "[[Not created yet]]", target: "Not created yet"),
        Case(input: "| a | [[Note\\|alias]] |", target: "Note", alias: "alias"),
        Case(input: "- [ ] task with [[Note]] @Tue", target: "Note"),
        Case(input: "# Heading with [[Note]]", target: "Note"),
        Case(input: "`code` then [[Note]]", target: "Note"),
        Case(input: "[[Note]]]", target: "Note"),
        Case(input: "text[[Note]]text", target: "Note"),
        Case(input: "[[a/b/c]]", target: "a/b/c"),
    ]

    @Test func parsingCases() {
        #expect(Self.cases.count == 25)
        let ex = WikilinkExtractor()
        for c in Self.cases {
            let links = ex.extract(from: c.input)
            #expect(links.count == 1, "\(c.input)")
            guard let l = links.first else { continue }
            #expect(l.target == c.target, "\(c.input)")
            #expect(l.heading == c.heading, "\(c.input)")
            #expect(l.blockID == c.blockID, "\(c.input)")
            #expect(l.alias == c.alias, "\(c.input)")
            #expect(l.isEmbed == c.embed, "\(c.input)")
        }
    }

    @Test func ignoresCodeAndMalformed() {
        let ex = WikilinkExtractor()
        let text = """
        `[[inline]]` and [[real]]
        ```
        [[fenced]]
        ```
        ~~~
        ![[tilde]]
        ~~~

            [[indented]]

        [[]] [[ ]] [[a [b]] \\[[escaped]]
        ---
        """
        #expect(ex.extract(from: text).map(\.target) == ["real"])
    }

    @Test func folderAndNameAccessors() {
        let l = WikilinkExtractor().extract(from: "[[Cell Biology/Glossary]] [[Plain]]")
        #expect(l[0].folder == "Cell Biology" && l[0].name == "Glossary")
        #expect(l[1].folder == nil && l[1].name == "Plain")
    }

    // MARK: Resolution

    static let notes = [
        NoteRef(id: "bio/glossary", courseID: "bio", name: "Glossary", path: "bio/Cell Biology/Glossary"),
        NoteRef(id: "chem/glossary", courseID: "chem", name: "Glossary", path: "chem/Glossary"),
        NoteRef(id: "bio/osmosis", courseID: "bio", name: "Osmosis", path: "bio/Osmosis"),
        NoteRef(id: "chem/bonds", courseID: "chem", name: "Bonds", path: "chem/Bonds"),
        NoteRef(id: "chem/bonds2", courseID: "chem", name: "bonds", path: "chem/extra/bonds"),
        NoteRef(id: "root/Ideas", courseID: nil, name: "Ideas"),
    ]

    func resolve(_ text: String, from course: CourseID?) -> WikilinkResolution {
        let ex = WikilinkExtractor()
        return ex.resolve(ex.extract(from: text)[0], from: course, in: Self.notes)
    }

    @Test func sameCourseWins() {
        #expect(resolve("[[Glossary]]", from: "bio") == .resolved("bio/glossary"))
        #expect(resolve("[[Glossary]]", from: "chem") == .resolved("chem/glossary"))
    }

    @Test func ambiguousAcrossVaultWhenNoSameCourse() {
        #expect(resolve("[[Glossary]]", from: nil) == .ambiguous(["bio/glossary", "chem/glossary"]))
        #expect(resolve("[[Glossary]]", from: "phys") == .ambiguous(["bio/glossary", "chem/glossary"]))
    }

    @Test func ambiguousInsideCourse() {
        #expect(resolve("[[Bonds]]", from: "chem") == .ambiguous(["chem/bonds", "chem/bonds2"]))
    }

    @Test func folderDisambiguates() {
        #expect(resolve("[[Cell Biology/Glossary]]", from: "chem") == .resolved("bio/glossary"))
        #expect(resolve("[[extra/bonds]]", from: "chem") == .resolved("chem/bonds2"))
        #expect(resolve("[[Cell/Glossary]]", from: "bio") == .notCreated(target: "Cell/Glossary"))
    }

    @Test func caseInsensitiveAndOutsideCourse() {
        #expect(resolve("[[osmosis]]", from: "chem") == .resolved("bio/osmosis"))
        #expect(resolve("[[ideas]]", from: "bio") == .resolved("root/Ideas"))
    }

    @Test func nonExistentTargetIsValid() {
        #expect(resolve("[[Future note]]", from: "bio") == .notCreated(target: "Future note"))
        #expect(resolve("[[#Heading]]", from: "bio") == .selfLink)
    }

    // MARK: Backlinks

    @Test func backlinksWithContext() {
        let osmosis = Self.notes[2]
        let sources = [
            NoteSource(ref: osmosis, text: "See [[Osmosis]] itself\n"),
            NoteSource(ref: Self.notes[0], text: "---\ntitle: G\n---\n# Terms\n\nDiffusion vs [[Osmosis#Definition|osmosis]] -- the key idea.\n```\n[[Osmosis]]\n```\n"),
            NoteSource(ref: Self.notes[3], text: "Nothing here [[Glossary]]\n"),
            NoteSource(ref: Self.notes[5], text: "[[Osmosis]] " + String(repeating: "x", count: 300)),
        ]
        let back = WikilinkExtractor().backlinks(to: "bio/osmosis", in: sources)
        #expect(back.map(\.sourceNoteID) == ["bio/glossary", "root/Ideas"])
        #expect(back[0].line == 6)
        #expect(back[0].snippet == "Diffusion vs [[Osmosis#Definition|osmosis]] -- the key idea.")
        #expect(back[0].link.heading == "Definition")
        #expect(back[1].snippet.count == WikilinkExtractor.maxSnippetLength + 1)
        #expect(back[1].snippet.hasSuffix("…"))
    }

    @Test func ambiguousLinksBacklinkEveryCandidate() {
        let src = NoteSource(ref: Self.notes[5], text: "x [[Glossary]]")
        let ex = WikilinkExtractor()
        #expect(ex.backlinks(to: "bio/glossary", in: Self.notes.map { NoteSource(ref: $0, text: "") } + [src]).count == 1)
        #expect(ex.backlinks(to: "chem/glossary", in: Self.notes.map { NoteSource(ref: $0, text: "") } + [src]).count == 1)
    }
}
