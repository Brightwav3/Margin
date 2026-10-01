import MarginCore
import Testing
@testable import MarginUI

@MainActor @Suite struct CoursesOverviewModelTests {
    private func loaded(_ mode: CoursesOverviewModel.Mode = .grid) async -> CoursesOverviewModel {
        let model = CoursesOverviewModel(env: .fixture(), mode: mode)
        await model.load()
        return model
    }

    @Test func loadsSixCoursesSortedByName() async {
        let m = await loaded()
        #expect(m.cards.count == 6)
        #expect(m.visibleCards.map(\.course.name).first == "Cell Biology")
        #expect(m.visibleCards.map(\.course.name) == m.visibleCards.map(\.course.name).sorted())
    }

    @Test func cardShowsNotesGradeAndNextClassWithItsNoteTitle() async throws {
        let m = await loaded()
        let bio = try #require(m.cards.first { $0.id == "bio" })
        // Placeholder notes (created from the timetable, no content) are not counted.
        #expect(bio.summary == "9 notes · A−")
        // Mon 28 Sep 13:24 → the next Bio class is Tue 10:00, named by its placeholder note.
        #expect(bio.next == "Tue 10:00 · Lecture 9 · Membrane transport")
        let chem = try #require(m.cards.first { $0.id == "chem" })
        // Chem's Monday 14:00 lab is later today, so it is next.
        #expect(chem.next == "Mon 14:00 · Lab")
        #expect(chem.summary == "2 notes")
    }

    @Test func semesterLineShowsCurrentWeek() async {
        let m = await loaded()
        #expect(m.currentWeek == 5)
        #expect(m.semesterLine == "Fall 2026 · Week 5 of \(m.semester?.weekCount ?? 0)")
    }

    @Test func facultyFilterAndGrouping() async {
        let m = await loaded()
        #expect(m.faculties == ["Sciences"])
        m.faculty = "Sciences"
        #expect(m.visibleCards.map(\.id) == ["bio"])
        m.faculty = nil
        m.grouping = .faculty
        let groups = m.groups
        #expect(groups.map(\.title) == ["Sciences", CoursesOverviewModel.otherFaculty])
        #expect(groups.map(\.cards.count) == [1, 5])
    }

    @Test func sortByNextClassPutsTodaysLaterClassesFirst() async {
        let m = await loaded()
        m.sort = .nextSession
        // 13:24 on Monday: Chem 14:00 today, then Bio Tue 10:00.
        #expect(m.visibleCards.prefix(2).map(\.id) == ["chem", "bio"])
    }

    @Test func weekFiveTimetable() async {
        let m = await loaded(.timetable)
        #expect(m.week == 5)
        #expect(m.blocks.count == 11)
        #expect(m.weekLine == "28 Sep – 2 Oct · 11 sessions")
        #expect(m.weekDays.first == LocalDate(year: 2026, month: 9, day: 28))
        #expect(m.weekDays.last == LocalDate(year: 2026, month: 10, day: 2))
    }

    @Test func weekNavigationStaysInsideTheSemester() async {
        let m = await loaded(.timetable)
        await m.showWeek(6)
        #expect(m.week == 6)
        #expect(m.weekLine.hasPrefix("5 – 9 Oct"))
        await m.showWeek(0)
        #expect(m.week == 1 && !m.canGoBack)
        await m.showWeek(999)
        #expect(m.week == m.semester?.weekCount && !m.canGoForward)
        await m.showThisWeek()
        #expect(m.week == 5)
    }

    @Test func hidingAKindRemovesItsBlocksButKeepsTheCount() async {
        let m = await loaded(.timetable)
        let labs = m.count(of: .labs)
        #expect(labs == 2)   // Chem lab Mon, Econ tutorial Fri
        m.toggle(.labs)
        #expect(m.blocks.count == 11 - labs)
        #expect(m.count(of: .labs) == labs)
        m.toggle(.labs)
        #expect(m.blocks.count == 11)
    }

    @Test func classTabTitleUsesItsNote() async throws {
        let m = await loaded(.timetable)
        let bio = try #require(m.blocks.first { $0.occurrence.session.courseID == "bio" })
        #expect(m.title(of: bio.occurrence) == "Lecture 9 — Membrane transport")
        let math = try #require(m.blocks.first { $0.occurrence.session.courseID == "math" })
        #expect(m.title(of: math.occurrence) == "Lecture · Mon 28 Sep")
    }

    @Test func timetableGeometryMatchesTheMockup() {
        // Block: 3 px below its start, length × 56 − 6 tall; „now“ 13:24 at (13.4 − 9) × 56.
        let block = TimetableView.blockFrame(start: LocalTime(hour: 10, minute: 0)!, lengthHours: 1.5)
        #expect(block.top == 59 && block.height == 78)
        #expect(abs(TimetableView.top(of: LocalTime(hour: 13, minute: 24)!) - 246.4) < 0.001)
        #expect(TimetableView.gridHeight == 560)
    }

    @Test func gridColumnsFollowWidth() {
        let layout = EqualColumnsLayout(minWidth: CoursesGridView.minCardWidth, maxColumns: 3,
                                        spacing: CoursesGridView.gap)
        #expect(layout.columns(for: 884) == 3)   // 1240 px window
        #expect(layout.columns(for: 544) == 2)   // 900 px window
        #expect(layout.columns(for: 300) == 1)
    }
}

@MainActor @Suite struct AppModelRouteTests {
    @Test func everythingShowsInTheActiveTabUnlessANewTabIsAsked() {
        let m = AppModel()
        let first = m.show(ShellTab(title: "Courses", route: "courses"))
        #expect(m.tabs.count == 1)
        // A course page, then a note: the same tab changes what it shows.
        #expect(m.show(ShellTab(title: "Cell Biology", route: "course/bio")) == first)
        #expect(m.show(ShellTab(title: "Lecture 8", route: "note/bio/lecture-8")) == first)
        #expect(m.tabs.count == 1 && m.activeTab?.route == "note/bio/lecture-8" && m.activeTab?.title == "Lecture 8")
        // A new tab only when asked; the same page may be open in two tabs.
        let second = m.show(ShellTab(title: "Today", route: "today"), newTab: true)
        #expect(second != first && m.tabs.count == 2 && m.activeTabID == second)
        #expect(m.show(ShellTab(title: "Lecture 8", route: "note/bio/lecture-8")) == second)
        #expect(m.tabs.count == 2)
    }

    @Test func historyGoesBackThroughWhatEachTabShowed() {
        let m = AppModel()
        let tab = m.show(ShellTab(title: "Today", route: "today"))
        m.show(ShellTab(title: "Cell Biology", route: "course/bio"))
        m.show(ShellTab(title: "Lecture 8", route: "note/bio/lecture-8"))
        m.goBack()
        #expect(m.activeTabID == tab && m.activeTab?.route == "course/bio" && m.activeTab?.title == "Cell Biology")
        m.goBack()
        #expect(m.activeTab?.route == "today")
        #expect(!m.canGoBack)
        m.goForward()
        #expect(m.activeTab?.route == "course/bio")
        // Navigating after going back drops the forward history.
        m.show(ShellTab(title: "Inbox", route: "inbox"))
        #expect(!m.canGoForward)
    }

    @Test func closingTheLastTabLeavesTheHomeTab() {
        let m = AppModel()
        m.homeTab = ShellTab(title: "Courses", route: "courses")
        let only = m.show(ShellTab(title: "Today", route: "today"))
        m.close(only)
        #expect(m.tabs.count == 1 && m.activeTab?.route == "courses" && m.activeTabID != only)
    }

    @Test func workspaceOpensPagesInTheActiveTabAndPlusMakesANewOne() {
        let w = Workspace(env: .fixture())
        #expect(w.shell.tabs.count == 1 && w.route == .courses)
        w.open(.today)
        w.open(.course("bio"))
        #expect(w.shell.tabs.count == 1 && w.route == .course("bio"))
        w.openInNewTab = true   // + in the title bar, then a choice
        w.open(.inbox)
        #expect(w.shell.tabs.count == 2 && w.route == .inbox && !w.openInNewTab)
        w.open(.graph)
        #expect(w.shell.tabs.count == 2 && w.route == .graph)
        w.open(.today, newTab: true)   // Open in new tab
        #expect(w.shell.tabs.count == 3)
    }
}
