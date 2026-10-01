import MarginCore
import Testing
@testable import MarginUI

@MainActor @Suite struct ScreensTests {
    @Test func gradesComputeTheSemesterAverageAndWhatIsNeeded() async throws {
        let m = GradesModel(env: .fixture())
        await m.load()
        #expect(m.rows.count == 6)
        let bio = try #require(m.rows.first { $0.id == "bio" })
        #expect(m.gradedWeight(bio) == 25)
        // Mockup: an A (93 %) needs 94 % on the remaining 75 %.
        #expect(Int(try #require(m.needed(bio)).rounded()) == 94)
        #expect(m.average?.letter == bio.summary?.letter)
        #expect(bio.next?.hasPrefix("Midterm") == true)
    }

    @Test func letterScale() {
        #expect(GradesModel.letter(93) == "A" && GradesModel.letter(90.5) == "A−" && GradesModel.letter(55) == "F")
    }

    @Test func searchFindsNotesAndFiltersByCourse() async {
        let m = SearchModel(env: .fixture(), query: "membrane")
        await m.run()
        #expect(!m.hits.isEmpty && m.hits.allSatisfy { $0.courseID == "bio" })
        m.courses = ["math"]
        await m.run()
        #expect(m.hits.allSatisfy { $0.courseID == "math" })
        m.query = ""
        m.courses = ["math", "bio"]
        m.kinds = [.lecture]
        await m.run()
        #expect(!m.hits.isEmpty && m.hits.allSatisfy { ["math", "bio"].contains($0.courseID) && $0.kind == .lecture })
    }

    @Test func highlightMarksTheMatchedRange() {
        let s = SearchModel.marked("Cell membrane", [HighlightRange(location: 5, length: 8)])
        #expect(String(s.characters) == "Cell membrane")
        #expect(s.runs.count == 2)
    }

    @Test func settingsRoundTrip() async throws {
        let env = AppEnvironment.fixture()
        let m = SettingsModel(env: env)
        await m.load()
        m.readableLineLength = false
        m.reminderMinutes = 15
        try await m.save()
        #expect(await env.settings.get(Settings.readableLineLength) == false)
        #expect(await env.settings.get(Settings.reminderMinutes) == 15)
    }

    @Test func workspaceRoutesEveryPlace() async {
        let w = Workspace(env: .fixture())
        for r: Route in [.today, .upcoming, .inbox, .graph, .grades, .archive, .search("x")] {   // settings open their own window
            w.open(r)
            #expect(w.route == r)
        }
        w.run(command: "timetable")
        #expect(w.route == .courses && w.courses.mode == .timetable)
    }
}
