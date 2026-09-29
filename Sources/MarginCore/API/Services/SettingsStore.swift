/// A typed app setting: a key, the type of its value and the value used until the user sets one.
///
/// Keys are declared once (see `Settings`), so a screen never spells a key by hand. The key is the
/// name in `.margin/settings.json`.
public struct Setting<Value: Codable & Sendable>: Sendable {
    public let key: String
    public let defaultValue: Value

    public init(_ key: String, default defaultValue: Value) {
        self.key = key; self.defaultValue = defaultValue
    }
}

/// One setting changed (`SettingsStore.changes`). Read the new value with `SettingsStore.get`.
public struct SettingChange: Codable, Sendable, Hashable {
    public let key: String
    public init(key: String) { self.key = key }
}

/// Persistent app settings (M10-21.B). Typed, with defaults; the vault implementation keeps them in
/// `.margin/settings.json` (spec 05 §1), the fixture in memory.
///
/// Implementations: `FixtureSettingsStore` and `VaultSettingsStore`. Rules both obey, checked by
/// `Tests/Conformance/SettingsStoreConformanceTests.swift`:
///
/// - **Defaults:** `get` of a key nobody set returns `Setting.defaultValue`. A stored value that
///   does not decode as the requested type also reads as the default (a hand-edited file never
///   stops the app) and is left in the file untouched.
/// - **Set and reset:** `set` stores the value, `reset` removes it again (back to the default).
///   Setting the value that is already stored (or resetting an unset key) changes nothing and
///   sends no change.
/// - **Changes propagate:** after `set` or `reset` returns, `get` returns the new value and
///   `changes` has sent one `SettingChange` for the key. A stream reports changes made after it was
///   created, not before.
/// - **Unknown keys are preserved:** keys of the file no `Setting` names (newer app version, other
///   tools) stay byte-compatible: they are written back with the same value.
/// - **Errors:** a store that cannot be written throws `.io`; a settings file that is not a JSON
///   object throws `.invalid` on `set` (it is not overwritten).
///
/// Settings are app data, not vault content: they take no `Actor`, `baseVersion` or `ChangeSet`.
public protocol SettingsStore: Sendable {
    /// The value of `setting`, or its default.
    func get<Value: Codable & Sendable>(_ setting: Setting<Value>) async -> Value

    /// Stores `value` for `setting`.
    func set<Value: Codable & Sendable>(_ setting: Setting<Value>, _ value: Value) async throws

    /// Removes the stored value of `setting`, so it reads as its default again.
    func reset<Value: Codable & Sendable>(_ setting: Setting<Value>) async throws

    /// Keys that changed, one element per change.
    var changes: AsyncStream<SettingChange> { get }
}

/// How a new tab shows a note (`Settings.defaultView`).
public enum EditorViewMode: String, Codable, Sendable, Hashable, CaseIterable {
    /// Live preview: formatting shown except on the line being edited.
    case editing
    case reading
    case source
}

/// The settings the app knows (mockup `margin-popups` 2g, Settings › Editor, and app behaviour).
public enum Settings {
    // Editor › Display
    /// Limit the width of notes so lines stay readable.
    public static let readableLineLength = Setting("editor.readableLineLength", default: true)
    /// The view a new tab opens a note in.
    public static let defaultView = Setting("editor.defaultView", default: EditorViewMode.editing)
    /// Show note properties above the title.
    public static let showProperties = Setting("editor.showProperties", default: true)
    /// Line numbers in source mode.
    public static let showLineNumbers = Setting("editor.showLineNumbers", default: false)

    // Files and links
    /// Rewrite wikilinks in other notes when a note is renamed (spec 05 §1, default on).
    public static let rewriteLinksOnRename = Setting("files.rewriteLinksOnRename", default: true)
    /// Seconds between file scans of the watcher.
    public static let watchInterval = Setting("files.watchInterval", default: 0.2)

    // Notifications
    /// Minutes before a class or a due time to remind.
    public static let reminderMinutes = Setting("reminders.minutesBefore", default: 10)
}
