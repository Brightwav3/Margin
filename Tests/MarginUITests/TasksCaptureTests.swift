import MarginCore
import Testing
@testable import MarginUI

@MainActor @Suite struct TasksModelTests {
    @Test func todayListsDueTasksAndTodaysClasses() async {
        let m = TasksModel(env: .fixture(), scope: .today)
        await m.load()
        #expect(m.groups.last?.title == "Today")
        #expect(m.groups.flatMap(\.tasks).map(\.text).contains("Problem set 4"))
        #expect(m.sessions.map(\.session.courseID) == ["math", "chem"])
    }

    @Test func upcomingGroupsByDayWithTomorrowFirst() async {
        let m = TasksModel(env: .fixture(), scope: .upcoming)
        await m.load()
        let groups = m.groups
        #expect(groups.first?.title == "Tomorrow")
        #expect(groups.first?.tasks.map(\.text).contains("Lab report: TLC") == true)
        #expect(groups.flatMap(\.tasks).contains { $0.kind == .exam && $0.text == "Midterm" })
        let days = groups.compactMap { LocalDate(iso: $0.id) }
        #expect(days == days.sorted())
    }

    @Test func courseFilter() async {
        let m = TasksModel(env: .fixture(), scope: .upcoming)
        await m.load()
        m.course = "bio"
        #expect(m.groups.flatMap(\.tasks).allSatisfy { $0.source.courseID == "bio" })
    }

    @Test func toggledTaskStaysStruckUntilReload() async throws {
        let m = TasksModel(env: .fixture(), scope: .today)
        await m.load()
        let task = try #require(m.groups.flatMap(\.tasks).first { $0.text == "Problem set 4" })
        try await m.toggle(task)
        #expect(m.tasks.first { $0.id == task.id }?.done == true)
        await m.load()
        #expect(!m.tasks.contains { $0.id == task.id && !$0.done })
    }

    @Test func dueLabels() {
        #expect(DueFormat.label(.today, due: nil) == "Today")
        #expect(DueFormat.label(.weekday(.friday), due: nil) == "Due Fri")
        #expect(DueFormat.label(.overdue(days: 3), due: nil) == "3 days late")
        #expect(DueFormat.isUrgent(.tomorrow) && !DueFormat.isUrgent(.weekday(.friday)))
    }
}

@MainActor @Suite struct CaptureAndInboxTests {
    @Test func captureParsesCourseAndTagsAndSavesToTheCourse() async throws {
        let env = AppEnvironment.fixture()
        let m = CaptureModel(env: env)
        m.open(prefill: "Read ch. 6 for bio #reading")
        await m.prepare()
        #expect(m.course?.id == "bio")
        #expect(m.draft.tags == ["reading"])
        #expect(m.primaryTitle == "Add to Cell Biology ↵")
        var toInbox: Bool?
        m.onSaved = { _, inbox in toInbox = inbox }
        await m.save()
        #expect(toInbox == false && !m.isOpen)
        #expect(try await env.tasks.tasks(course: "bio").contains { $0.text.contains("Read ch. 6") })
    }

    @Test func droppingTheCourseChipSendsItToTheInbox() async throws {
        let env = AppEnvironment.fixture()
        let before = try await env.inbox.items().count
        let m = CaptureModel(env: env)
        m.open(prefill: "Buy lab goggles for chem")
        await m.prepare()
        m.dropped.insert(.course)
        #expect(m.primaryTitle == "Add to Inbox ↵")
        await m.save()
        #expect(try await env.inbox.items().count == before + 1)
    }

    @Test func emptyCaptureIsRefused() async {
        let m = CaptureModel(env: .fixture())
        m.open()
        await m.save()
        #expect(m.error != nil && m.isOpen)
    }

    @Test func inboxTriageMovesTheItemToTheCourse() async throws {
        let env = AppEnvironment.fixture()
        let m = InboxModel(env: env)
        await m.load()
        let count = m.items.count
        let item = try #require(m.current)
        m.course = "bio"
        m.keepAs = .task
        m.when = .tomorrow
        let courses = try await env.courses.courses(query: nil)
        let name = try await m.move(courses: courses)
        #expect(name == "Cell Biology")
        #expect(m.items.count == count - 1 && !m.items.contains { $0.id == item.id })
    }

    @Test func beforeNextLectureIsTheDayBeforeTheClass() async throws {
        let env = AppEnvironment.fixture()
        let m = InboxModel(env: env)
        m.course = "bio"
        let courses = try await env.courses.courses(query: nil)
        // Mon 28 Sep: next Bio class Tue 29 → due Mon 28 (today).
        #expect(m.due(.beforeLecture, courses: courses) == LocalDate(year: 2026, month: 9, day: 28))
        #expect(m.nextLectureDay(courses: courses) == LocalDate(year: 2026, month: 9, day: 29))
    }
}
