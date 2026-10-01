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

/// The local profile (Settings › Profile, account popup). Kept in the vault, never sent anywhere.
public struct Profile: Codable, Sendable, Hashable {
    public var name: String
    public var school: String
    public var programme: String
    /// 0 = not set.
    public var yearOfStudy: Int
    /// BCP 47 code (`cs`, `en`); empty = the system's.
    public var language: String
    /// IANA time zone (`Europe/Prague`); empty = the system's.
    public var timeZone: String

    public init(name: String = "", school: String = "", programme: String = "", yearOfStudy: Int = 0,
                language: String = "", timeZone: String = "") {
        self.name = name; self.school = school; self.programme = programme; self.yearOfStudy = yearOfStudy
        self.language = language; self.timeZone = timeZone
    }

    /// „AK“ for „Anna Kováčová“; „ME“ when there is no name.
    public var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "ME" : String(parts).uppercased()
    }
}

/// Light, dark or follow the system (Settings › Appearance).
public enum AppTheme: String, Codable, Sendable, Hashable, CaseIterable { case system, light, dark }

/// Where the app opens (Settings › General).
public enum StartupPlace: String, Codable, Sendable, Hashable, CaseIterable { case courses, today, upcoming, inbox }

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

    /// Typing `**` or `(` adds the closing pair.
    public static let autoPair = Setting("editor.autoPair", default: true)
    /// Enter continues a list, Tab nests it.
    public static let smartLists = Setting("editor.smartLists", default: true)
    /// Note text size in points (⌘+ / ⌘− change it per window).
    public static let fontSize = Setting("editor.fontSize", default: 16.0)

    /// Folder (vault-relative) for pasted images and PDFs; empty = the course's `_files/`.
    public static let attachmentsFolder = Setting("files.attachmentsFolder", default: "")
    /// Edits from Finder, Git or other apps appear immediately (the file watcher).
    public static let watchExternalChanges = Setting("files.watchExternalChanges", default: true)

    // Notifications
    /// Minutes before a class or a due time to remind.
    public static let reminderMinutes = Setting("reminders.minutesBefore", default: 10)

    // Profile and general
    /// The local profile.
    public static let profile = Setting("profile", default: Profile())
    /// The page the app opens on.
    public static let openOnStartup = Setting("general.openOnStartup", default: StartupPlace.courses)
    /// Ask before moving a note or course to the trash.
    public static let confirmBeforeDeleting = Setting("general.confirmBeforeDeleting", default: true)
    /// ⇧⌘Space opens quick capture from any app.
    public static let globalQuickCapture = Setting("general.globalQuickCapture", default: true)

    // Appearance
    public static let theme = Setting("appearance.theme", default: AppTheme.system)

    // Semesters
    /// Create the lecture note of a class when it starts (a draft until then).
    public static let autoLectureNotes = Setting("semesters.autoLectureNotes", default: false)
}
