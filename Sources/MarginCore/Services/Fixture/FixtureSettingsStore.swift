import Foundation

/// `SettingsStore` in memory (previews, gallery, tests). Same observable behaviour as
/// `VaultSettingsStore` (contract rules 2 and 3).
public actor FixtureSettingsStore: SettingsStore {
    private var document = SettingsDocument()
    nonisolated let broadcaster = Broadcaster<SettingChange>()

    public init() {}

    public func get<Value: Codable & Sendable>(_ setting: Setting<Value>) async -> Value {
        document.value(for: setting)
    }

    public func set<Value: Codable & Sendable>(_ setting: Setting<Value>, _ value: Value) async throws {
        if try document.set(setting, value) { broadcaster.send(SettingChange(key: setting.key)) }
    }

    public func reset<Value: Codable & Sendable>(_ setting: Setting<Value>) async throws {
        if document.remove(key: setting.key) { broadcaster.send(SettingChange(key: setting.key)) }
    }

    public nonisolated var changes: AsyncStream<SettingChange> { broadcaster.subscribe() }

    nonisolated func finish() { broadcaster.finishAll() }
}
