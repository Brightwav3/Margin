import MarginCore
import Testing
@testable import MarginUI

@MainActor @Suite struct CourseDetailModelTests {
    private func loaded() async -> CourseDetailModel {
        let m = CourseDetailModel(env: .fixture(), course: "bio")
        await m.load()
        return m
    }

    @Test func galleryHasTheNextClassAndNotesNewestFirst() async throws {
        let m = await loaded()
        let first = try #require(m.visibleCards.first)
        #expect(first.isUpcoming && first.kind == "Lecture 9" && first.theme == "Membrane transport")
        #expect(first.meta == "Tomorrow · Sci 204")
        #expect(m.visibleCards.filter(\.isUpcoming).count == 1)
        let lecture8 = try #require(m.cards.first { $0.theme == "Cell membrane" })
        #expect(lecture8.date == "Thu 24 Sep" && lecture8.kind == "Lecture 8")
        #expect(lecture8.badge?.text == "2 open")
        #expect(m.cards.first { $0.theme == "Organelles" }?.badge?.text == "Done")
        #expect(m.cards.first { $0.theme == "Microscopy" }?.meta == "3 images")
        // Selected by default: the newest note that is not upcoming.
        #expect(m.selected == m.visibleCards.first { !$0.isUpcoming }?.id)
    }

    @Test func filtersAndOrder() async {
        let m = await loaded()
        m.filter = .labs
        #expect(m.visibleCards.map(\.theme) == ["Microscopy"])
        m.filter = .study
        #expect(m.visibleCards.allSatisfy { $0.kind == "Study note" })
        m.filter = .all
        m.newestFirst = false
        #expect(m.visibleCards.first?.theme == "Proteins and enzymes")
    }

    @Test func subtitleAndSessions() async {
        let m = await loaded()
        #expect(m.subtitle.hasPrefix("BIO 201 · Dr. Okafor · "))
        #expect(m.subtitle.hasSuffix("A− \(m.grade?.percent ?? 0)%"))
        #expect(m.sessionsLine == "Tue, Thu 10:00 · Sci 204")
    }

    @Test func comingUpListsExamGradedItemAndNextClassByDate() async {
        let m = await loaded()
        let titles = m.comingUp.map(\.title)
        #expect(titles.contains("Midterm"))
        #expect(titles.contains("Problem set 3"))
        #expect(titles.contains("Lecture 9 — Membrane transport"))
        #expect(m.comingUp.first?.distance == "1d")
        #expect(m.comingUp.map(\.date) == m.comingUp.map(\.date).sorted())
    }

    @Test func gradePartsFollowTheGradingScheme() async {
        let m = await loaded()
        let parts = GradeGroups.make(course: m.course, grades: m.grades)
        #expect(parts.map(\.label) == ["Problem sets", "Lab reports", "Midterm", "Final exam"])
        #expect(parts[0].score == "37/40")
        #expect(parts[2].score == "Thu 1 Oct")
    }

    @Test func createdNoteAppearsInTheGallery() async throws {
        let m = await loaded()
        let before = m.cards.count
        let note = try #require(try await m.createNote(title: "Osmosis"))
        #expect(note.title == "Osmosis")
        #expect(m.cards.count == before + 1)
    }

    @Test func routesRoundTrip() {
        let routes: [Route] = [.courses, .course("bio"), .note("bio/lecture-8"), .inbox, .today, .upcoming, .graph,
                               .search("osmosis"), .grades, .archive, .settings,
                               .draft(course: "bio", date: LocalDate(year: 2026, month: 10, day: 1)!, title: "Lecture 10")]
        for r in routes { #expect(Route(key: r.key) == r) }
    }
}
