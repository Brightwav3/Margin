import MarginCore
import Testing
@testable import MarginUI

/// Settings window of Account v3 and the settings it applies (M11-05.U).
@MainActor @Suite(.serialized) struct AccountSettingsTests {
    private func settle(until done: () -> Bool) async {
        for _ in 0..<100 where !done() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func theProfileIsSavedAndShownOnTheRail() async throws {
        let w = Workspace(env: .fixture())
        let m = w.settingsModel()
        await m.load()
        m.profile = Profile(name: "Šimon Zelenka", school: "Masarykova univerzita", yearOfStudy: 1)
        try await m.save()
        w.applySettings()
        await settle { w.profile.name == "Šimon Zelenka" }
        #expect(w.rail.initials == "ŠZ")
        #expect(await w.env.settings.get(Settings.profile).school == "Masarykova univerzita")
    }

    @Test func deletingWithoutConfirmationGoesStraightToTheTrash() async throws {
        let w = Workspace(env: .fixture())
        await w.courses.load()
        try await w.env.settings.set(Settings.confirmBeforeDeleting, false)
        w.applySettings()
        await settle { !w.confirmBeforeDeleting }
        let note = try #require(try await w.env.notes.notes(course: "math").first)
        w.requestDelete(note)
        #expect(w.dialog == nil)
        var gone = false
        for _ in 0..<100 where !gone {
            gone = (try? await w.env.notes.notes(course: "math").contains { $0.id == note.id }) == false
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(gone)
    }

    @Test func autoPairingWrapsAndSkipsBeforeWords() {
        EditorTyping.autoPair = true
        #expect(EditorTyping.pair(typed: "(", selected: "", next: nil)?.text == "()")
        #expect(EditorTyping.pair(typed: "(", selected: "", next: nil)?.caret == 1)
        #expect(EditorTyping.pair(typed: "[", selected: "osmosis", next: nil)?.text == "[osmosis]")
        #expect(EditorTyping.pair(typed: "(", selected: "", next: "w") == nil)
        #expect(EditorTyping.pair(typed: "a", selected: "", next: nil) == nil)
        EditorTyping.autoPair = false
        #expect(EditorTyping.pair(typed: "(", selected: "", next: nil) == nil)
        EditorTyping.autoPair = true
    }

    @Test func fileRecoveryListsRecentSnapshots() async throws {
        let w = Workspace(env: .fixture())
        _ = try await w.env.history.snapshot(note: "bio/lecture-9", reason: .close)
        let m = w.settingsModel()
        await m.loadFiles()
        #expect(m.snapshots.first?.noteID == "bio/lecture-9")
        #expect(m.snapshotTitles["bio/lecture-9"] != nil)
        #expect((m.stats?.noteCount ?? 0) > 0)
    }
}
