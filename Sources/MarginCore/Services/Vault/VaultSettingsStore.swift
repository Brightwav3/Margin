import Foundation

/// `SettingsStore` over `.margin/settings.json` (spec 05 §1). Every read looks at the file, so an edit
/// by another program shows at the next `get`; every write is atomic through `VaultStore` with the
/// version that was read, and retried when the file changed in between.
public actor VaultSettingsStore: SettingsStore {
    static let file = ".margin/settings.json"
    private let store: VaultStore
    nonisolated let broadcaster = Broadcaster<SettingChange>()

    init(store: VaultStore) { self.store = store }

    public func get<Value: Codable & Sendable>(_ setting: Setting<Value>) async -> Value {
        guard let path = try? VaultPath(Self.file), let text = try? await store.read(path).content,
              let document = try? SettingsDocument(parsing: text)
        else { return setting.defaultValue }
        return document.value(for: setting)
    }

    public func set<Value: Codable & Sendable>(_ setting: Setting<Value>, _ value: Value) async throws {
        try await edit(key: setting.key) { try $0.set(setting, value) }
    }

    public func reset<Value: Codable & Sendable>(_ setting: Setting<Value>) async throws {
        try await edit(key: setting.key) { $0.remove(key: setting.key) }
    }

    public nonisolated var changes: AsyncStream<SettingChange> { broadcaster.subscribe() }

    nonisolated func finish() { broadcaster.finishAll() }

    /// Applies `change` to the stored document; writes and announces only when it returns `true`.
    private func edit(key: String, _ change: (inout SettingsDocument) throws -> Bool) async throws {
        let path = try VaultPath(Self.file)
        var attempts = 0
        while true {
            attempts += 1
            let existing = try? await store.read(path)
            var document = try SettingsDocument(parsing: existing?.content)
            guard try change(&document) else { return }
            do {
                if let existing { try await store.write(path, content: document.render(), expectedVersion: existing.version) }
                else { try await store.create(path, content: document.render()) }
                break
            } catch MarginError.conflict where attempts < 3 {
                continue   // changed on disk meanwhile: read again
            }
        }
        broadcaster.send(SettingChange(key: key))
    }
}
