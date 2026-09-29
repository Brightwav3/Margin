import Foundation
import Testing
@testable import MarginCore

/// M10-16.B: a created course has a folder and a `_course.md` that passes validation and reads back
/// as the course that was planned.
@Suite struct CourseFactoryTests {
    private let semester = Fixtures.week5.semester
    private let sampleEntries: [VaultCourseModel.Entry] = Fixtures.week5.courses.map {
        .init(course: $0, semesterFolder: "Fall 2026", folder: VaultPath.filename(fromTitle: $0.name))
    }

    private func plan(_ new: NewCourse, entries: [VaultCourseModel.Entry]? = nil) throws -> CourseFactory.Plan {
        try CourseFactory.plan(new, semesters: [semester], entries: entries ?? sampleEntries)
    }

    @Test func aPlannedCourseValidatesAndReadsBackAsThePlan() throws {
        let variants: [NewCourse] = [
            NewCourse(name: "Statistics", semester: "fall-2026"),
            NewCourse(name: "Intro: to \"Logic\" / #1", semester: "fall-2026", code: "PHI 110", professor: "Dr. Ünal", room: "A: 3",
                      faculty: "Arts", credits: 3, icon: "menu_book", color: "hist",
                      sessions: [NewSession(day: .friday, start: .literal(8, 15), lengthHours: 2.25, kind: "Seminar", room: "B 1"),
                                 NewSession(day: .monday, start: .literal(16, 0))]),
            NewCourse(name: "true", semester: "fall-2026"),           // a name YAML would read as a boolean
            NewCourse(name: "2026", semester: "fall-2026", code: "007"),
        ]
        for new in variants {
            let p = try plan(new)
            #expect(CourseValidator.validate(p.text).isEmpty, "\(new.name): \(CourseValidator.validate(p.text))")
            let fm = try #require(Frontmatter.parse(p.text).frontmatter)
            let parsed = try #require(VaultCourseModel.parseCourse(fm, semesterFolder: "Fall 2026", folder: p.folder.lastComponent))
            #expect(parsed == p.course, "\(new.name)")
            #expect(p.path.rawValue == "Fall 2026/\(p.folder.lastComponent)/_course.md")
        }
    }

    @Test func theDefaultScheduleIsOneMondayLecture() throws {
        let p = try plan(NewCourse(name: "Statistics", semester: "fall-2026"))
        #expect(p.course.sessions.map(\.id) == ["statistics-mon-1000"])
        #expect(p.course.sessions[0].lengthHours == 1.5 && p.course.sessions[0].kind == "Lecture")
        #expect(p.course.id == "statistics" && p.course.style.icon == "school")
    }

    @Test func idsAreUniqueAndColoursCycle() throws {
        var entries = sampleEntries
        let first = try plan(NewCourse(name: "Cell  Biology", semester: "fall-2026"), entries: entries)   // folder differs, slug is taken
        #expect(first.course.id == "cell-biology" || first.course.id == "cell-biology-2")
        entries.append(.init(course: first.course, semesterFolder: "Fall 2026", folder: first.folder.lastComponent))
        let second = try plan(NewCourse(name: "Cell   Biology", semester: "fall-2026"), entries: entries)
        #expect(!Set(entries.map(\.course.id)).contains(second.course.id))
        // All six palette keys are taken by the sample courses: the colour wraps around to the first.
        #expect(first.course.style.color == CoursePalette.keys[0])
        let none = try plan(NewCourse(name: "Fresh", semester: "fall-2026"), entries: [])
        #expect(none.course.style.color == CoursePalette.keys[0])
    }

    @Test func badInputIsRejectedBeforeAnythingIsWritten() {
        func code(_ new: NewCourse, semesters: [Semester]? = nil) -> String? {
            do { _ = try CourseFactory.plan(new, semesters: semesters ?? [semester], entries: sampleEntries); return nil }
            catch let e as MarginError { return e.code } catch { return "other" }
        }
        var archived = semester; archived.isArchived = true
        #expect(code(NewCourse(name: "", semester: "fall-2026")) == "invalid")
        #expect(code(NewCourse(name: "///", semester: "fall-2026")) == "invalid")
        #expect(code(NewCourse(name: String(repeating: "x", count: 121), semester: "fall-2026")) == "invalid")
        #expect(code(NewCourse(name: "A\nB", semester: "fall-2026")) == "invalid")
        #expect(code(NewCourse(name: "Fine", semester: "fall-2026", icon: "Bad Icon")) == "invalid")
        #expect(code(NewCourse(name: "Fine", semester: "fall-2026", color: "nope")) == "invalid")
        #expect(code(NewCourse(name: "Fine", semester: "fall-2026", sessions: [NewSession(day: .monday, start: .literal(9), lengthHours: 13)])) == "invalid")
        #expect(code(NewCourse(name: "Fine", semester: "fall-2026", sessions: [NewSession(day: .monday, start: .literal(9)), NewSession(day: .monday, start: .literal(9))])) == "invalid")
        #expect(code(NewCourse(name: "Fine", semester: "spring-2030")) == "notFound")
        #expect(code(NewCourse(name: "Fine", semester: "fall-2026"), semesters: [archived]) == "readOnly")
        #expect(code(NewCourse(name: "cell biology", semester: "fall-2026")) == "conflict")
        #expect(code(NewCourse(name: "Fine", semester: "fall-2026")) == nil)
    }

    @Test func theValidatorFindsWhatIsWrong() {
        let cases: [(String, String)] = [
            ("no frontmatter\n", "no frontmatter"),
            ("---\ncode: X\n---\n", "'name'"),
            ("---\nname: \"  \"\n---\n", "'name'"),
            ("---\nname: A\nid: Bad Id\n---\n", "slug"),
            ("---\nname: A\ncredits: -1\n---\n", "credits"),
            ("---\nname: A\nname: B\n---\n", "duplicated"),
            ("---\nname: A\nsessions:\n  - {day: Xyz, time: \"10:00\"}\n---\n", "'day'"),
            ("---\nname: A\nsessions:\n  - {day: Tue, time: \"25:99\"}\n---\n", "'time'"),
            ("---\nname: A\nsessions:\n  - {day: Tue, time: \"10:00\", length: 0}\n---\n", "'length'"),
            ("---\nname: A\nsessions:\n  - {day: Tue, time: \"10:00\"}\n  - {day: Tue, time: \"10:00\"}\n---\n", "two sessions"),
            ("---\nname: A\nexams:\n  - {title: Midterm}\n---\n", "'date'"),
            ("---\nname: A\ngrading:\n  - {label: X, weight: 60%}\n  - {label: Y, weight: 50%}\n---\n", "110%"),
            ("---\nname: A\ngrading:\n  - {weight: 10%}\n---\n", "'label'"),
        ]
        for (text, expected) in cases {
            let problems = CourseValidator.validate(text).map(\.message)
            #expect(problems.contains { $0.contains(expected) }, "\(text.prefix(40)) → \(problems)")
        }
        let good = "---\nname: A\ncolor: bio\nunknown: kept\nsessions:\n  - {day: Tue, time: \"10:00\", length: 1.5}\ngrading:\n  - {label: X, weight: 100%}\n---\n\nBody\n"
        #expect(CourseValidator.validate(good).isEmpty)
        // The sample vault's own courses are valid.
        for c in Fixtures.week5.courses { #expect(CourseValidator.validate(SampleVaultGenerator.courseFile(c)).isEmpty, "\(c.id)") }
    }

    @Test func creatingWritesFolderAndFileAndSurvivesARestart() async throws {
        let v = try await CourseVault.open(sample: false)
        defer { withExtendedLifetime(v) {} }
        let cs = try await v.writer.create(NewCourse(name: "Statistics", semester: "fall-2026", code: "STA 101"),
                                           actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        #expect(cs.entries.map(\.path) == ["Fall 2026/Statistics/_course.md"])
        let onDisk = v.text("Fall 2026/Statistics/_course.md")
        #expect(CourseValidator.validate(onDisk).isEmpty)
        #expect(ContentHash(of: onDisk).hex == cs.entries[0].afterHash)
        await v.shutdown()

        // A new backend over the same folder finds the same course.
        let again = try await CourseVault.reopen(v.dir)
        let course = try await again.catalog.course(id: "statistics")
        #expect(course.name == "Statistics" && course.code == "STA 101" && course.sessions.count == 1)
        // A second course of the same name cannot take the folder.
        let code = await errorCode { try await again.writer.create(NewCourse(name: "Statistics", semester: "fall-2026"), actor: .user,
                                                                    baseVersion: nil, dryRun: false, idempotencyKey: nil) }
        #expect(code == "conflict")
        await again.shutdown()
    }

    @Test func aFolderThatAlreadyExistsOnDiskIsNeverOverwritten() async throws {
        let v = try await CourseVault.open(sample: false)
        defer { withExtendedLifetime(v) {} }
        try v.dir.seed("Fall 2026/Statistics/Notes.md", Data("# mine\n".utf8))    // a folder without _course.md
        let code = await errorCode { try await v.writer.create(NewCourse(name: "Statistics", semester: "fall-2026"), actor: .user,
                                                               baseVersion: nil, dryRun: false, idempotencyKey: nil) }
        #expect(code == "conflict")
        #expect(v.dir.exists("Fall 2026/Statistics/Notes.md") && !v.dir.exists("Fall 2026/Statistics/_course.md"))
        await v.shutdown()
    }
}
