import Foundation
import Testing
@testable import MarginCore

/// `SettingsStore` (M10-21.B): the same rules for `FixtureSettingsStore` and `VaultSettingsStore`.
@Suite struct SettingsStoreConformanceTests {
    private struct Custom: Codable, Sendable, Equatable { var name: String; var sizes: [Int] }
    private static let custom = Setting("test.custom", default: Custom(name: "none", sizes: []))

    @Test(arguments: HarnessKind.allCases)
    func unsetKeysReadAsTheirDefaults(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            #expect(await h.settings.get(Settings.readableLineLength) == true)
            #expect(await h.settings.get(Settings.defaultView) == .editing)
            #expect(await h.settings.get(Settings.showProperties) == true)
            #expect(await h.settings.get(Settings.showLineNumbers) == false)
            #expect(await h.settings.get(Settings.rewriteLinksOnRename) == true)
            #expect(await h.settings.get(Settings.watchInterval) == 0.2)
            #expect(await h.settings.get(Settings.reminderMinutes) == 10)
            #expect(await h.settings.get(Self.custom) == Custom(name: "none", sizes: []))
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func setValueIsReadBackAndReportedOnce(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let changes = h.settings.changes
            try await h.settings.set(Settings.readableLineLength, false)
            try await h.settings.set(Settings.reminderMinutes, 25)
            try await h.settings.set(Settings.defaultView, .source)
            try await h.settings.set(Settings.watchInterval, 0.5)
            try await h.settings.set(Self.custom, Custom(name: "x", sizes: [1, 2]))
            #expect(await h.settings.get(Settings.readableLineLength) == false)
            #expect(await h.settings.get(Settings.reminderMinutes) == 25)
            #expect(await h.settings.get(Settings.defaultView) == .source)
            #expect(await h.settings.get(Settings.watchInterval) == 0.5)
            #expect(await h.settings.get(Self.custom) == Custom(name: "x", sizes: [1, 2]))
            #expect(await h.settings.get(Settings.showProperties) == true)   // others untouched

            let seen = await collect(from: changes, timeout: 5) { $0.key == Self.custom.key }
            #expect(seen.map(\.key) == [Settings.readableLineLength.key, Settings.reminderMinutes.key,
                                        Settings.defaultView.key, Settings.watchInterval.key, Self.custom.key])
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func settingTheSameValueSendsNothing(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            try await h.settings.set(Settings.reminderMinutes, 30)
            let changes = h.settings.changes
            try await h.settings.set(Settings.reminderMinutes, 30)     // same value
            try await h.settings.reset(Settings.showLineNumbers)       // never set
            try await h.settings.set(Settings.reminderMinutes, 5)
            let first = await next(from: changes, timeout: 5)
            #expect(first?.key == Settings.reminderMinutes.key)
            #expect(await h.settings.get(Settings.reminderMinutes) == 5)
            // Only the real change arrived: the next element does not come.
            let more = await next(from: changes, timeout: 0.3)
            #expect(more == nil)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func resetGoesBackToTheDefaultAndReports(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            try await h.settings.set(Settings.showLineNumbers, true)
            let changes = h.settings.changes
            try await h.settings.reset(Settings.showLineNumbers)
            #expect(await h.settings.get(Settings.showLineNumbers) == false)
            #expect(await next(from: changes, timeout: 5)?.key == Settings.showLineNumbers.key)
        }
    }

    @Test(arguments: HarnessKind.allCases)
    func everyStreamGetsEveryChange(kind: HarnessKind) async throws {
        try await withHarness(kind) { h in
            let a = h.settings.changes, b = h.settings.changes
            try await h.settings.set(Settings.showProperties, false)
            #expect(await next(from: a, timeout: 5)?.key == Settings.showProperties.key)
            #expect(await next(from: b, timeout: 5)?.key == Settings.showProperties.key)
        }
    }

    // MARK: Vault file

    @Test func vaultKeepsUnknownKeysAndWritesAJSONObject() async throws {
        try await withHarness(.vault) { h in
            try h.writeFile(".margin/settings.json", """
                {"future.feature": {"a": [1, 2, {"b": null}], "on": true}, "other": "text"}
                """)
            try await h.settings.set(Settings.readableLineLength, false)
            try await h.settings.set(Settings.reminderMinutes, 15)
            try await h.settings.reset(Settings.reminderMinutes)
            let text = try #require(h.readFile(".margin/settings.json"))
            let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            #expect(object["editor.readableLineLength"] as? Bool == false)
            #expect(object["reminders.minutesBefore"] == nil)
            #expect(object["other"] as? String == "text")
            let future = try #require(object["future.feature"] as? [String: Any])
            #expect(future["on"] as? Bool == true)
            let list = try #require(future["a"] as? [Any])
            #expect(list.count == 3)
            #expect((list[2] as? [String: Any])?["b"] is NSNull)
        }
    }

    @Test func vaultSeesOutsideEditsAndSurvivesReopening() async throws {
        try await withHarness(.vault) { h in
            try await h.settings.set(Settings.defaultView, .reading)
            try h.writeFile(".margin/settings.json", #"{"editor.defaultView": "source"}"#)
            #expect(await h.settings.get(Settings.defaultView) == .source)
            try await h.settings.set(Settings.showLineNumbers, true)
            #expect(h.readFile(".margin/settings.json")?.contains("editor.showLineNumbers") == true)
        }
    }

    @Test func badValuesAndFilesNeverStopTheApp() async throws {
        try await withHarness(.vault) { h in
            try h.writeFile(".margin/settings.json", #"{"reminders.minutesBefore": "soon", "editor.defaultView": "sideways"}"#)
            #expect(await h.settings.get(Settings.reminderMinutes) == 10)
            #expect(await h.settings.get(Settings.defaultView) == .editing)

            let broken = "not json {"
            try h.writeFile(".margin/settings.json", broken)
            #expect(await h.settings.get(Settings.readableLineLength) == true)
            await #expect(throws: MarginError.self) { try await h.settings.set(Settings.readableLineLength, false) }
            #expect(h.readFile(".margin/settings.json") == broken, "a broken file is not overwritten")
        }
    }

    @Test func vaultCreatesTheFileOnFirstSet() async throws {
        let folder = TempFolder()
        let env = try await AppEnvironment.vault(at: try makeEmptyVault(folder.url))
        try await env.settings.set(Settings.reminderMinutes, 20)
        let text = try String(contentsOf: folder.url.appendingPathComponent(".margin/settings.json"), encoding: .utf8)
        #expect(text.contains("\"reminders.minutesBefore\" : 20"))
        await env.shutdown()
    }

    private func makeEmptyVault(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
