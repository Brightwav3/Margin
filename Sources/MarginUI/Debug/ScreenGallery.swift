import SwiftUI

/// A screen that can be opened on its own with fixture data, under its mockup ID (`00-overview.md` §4).
public struct MarginScreen: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let milestone: String
    let make: @MainActor @Sendable () -> AnyView

    init(_ id: String, _ title: String, milestone: String, make: @escaping @MainActor @Sendable () -> AnyView) {
        self.id = id
        self.title = title
        self.milestone = milestone
        self.make = make
    }

    @MainActor public func view() -> AnyView { make() }
}

public enum MarginScreens {
    /// Mockup size of every screen.
    public static let size = CGSize(width: 1240, height: 820)

    public static let all: [MarginScreen] = [
        MarginScreen("system", "System: type, colours, tiles, controls", milestone: "M0") { AnyView(SystemScreen()) },
        MarginScreen("shell", "Shell: courses navigation, empty content", milestone: "M1") {
            AnyView(ShellPreviewScreen(activeTab: "Courses", railActive: "home", sidebar: ShellPresets.grid,
                                       inspector: ShellPresets.courseInspector))
        },
        MarginScreen("shell-notes", "Shell: course, Notes space, note inspector", milestone: "M1") {
            AnyView(ShellPreviewScreen(activeTab: "Cell Biology", railActive: "bio", sidebar: ShellPresets.course,
                                       inspector: ShellPresets.noteInspector, inspectorOpen: true, page: .notes,
                                       inspectorTab: .backlinks))
        },
        MarginScreen("shell-course", "Shell: course navigation, course inspector (Agent)", milestone: "M1") {
            AnyView(ShellPreviewScreen(activeTab: "Cell Biology", railActive: "bio", sidebar: ShellPresets.course,
                                       inspector: ShellPresets.courseInspector, inspectorOpen: true))
        },
        MarginScreen("shell-collapsed", "Shell: collapsed sidebar, inspector (Outline)", milestone: "M1") {
            AnyView(ShellPreviewScreen(activeTab: "Cell Biology", railActive: "bio", sidebar: ShellPresets.course,
                                       inspector: ShellPresets.noteInspector, collapsed: true, inspectorOpen: true,
                                       inspectorTab: .outline))
        },
        MarginScreen("1a", "Courses home: card grid", milestone: "M3") {
            AnyView(WorkspaceView(env: .fixture(), mode: .grid))
        },
        MarginScreen("1b", "Courses home: timetable", milestone: "M3") {
            AnyView(WorkspaceView(env: .fixture(), mode: .timetable))
        },
        MarginScreen("2c", "Course: gallery of lecture notes, course inspector", milestone: "M4") {
            AnyView(WorkspaceView(env: .fixture(), start: .course("bio"), inspectorOpen: true))
        },
        MarginScreen("course-tasks", "Course: tasks page", milestone: "M4") {
            AnyView(CoursePageScreen(page: .tasks))
        },
        MarginScreen("course-grades", "Course: grades page", milestone: "M4") {
            AnyView(CoursePageScreen(page: .grades))
        },
        MarginScreen("3a", "Note editor: live, properties, note inspector", milestone: "M6a") {
            AnyView(WorkspaceView(env: .fixture(), start: .note("bio/lecture-8"), inspectorOpen: true))
        },
        MarginScreen("3a-lists", "Note editor: lists, nesting, footnotes (Obsidian-like)", milestone: "M6b") {
            AnyView(ListsSampleScreen())
        },
        MarginScreen("3a-source", "Note editor: source mode", milestone: "M6a") {
            AnyView(EditorModeScreen(mode: .source))
        },
        MarginScreen("3a-reading", "Note editor: reading view", milestone: "M6a") {
            AnyView(EditorModeScreen(mode: .reading))
        },
        MarginScreen("today", "Today: overdue, today, classes (proposal)", milestone: "M7") {
            AnyView(WorkspaceView(env: .fixture(), start: .today))
        },
        MarginScreen("upcoming", "Upcoming: next days and later (proposal)", milestone: "M7") {
            AnyView(WorkspaceView(env: .fixture(), start: .upcoming))
        },
        MarginScreen("5a", "Quick entry over the Inbox", milestone: "M8") { AnyView(CaptureScreen()) },
        MarginScreen("5b", "Inbox triage", milestone: "M8") {
            AnyView(WorkspaceView(env: .fixture(), start: .inbox))
        },
        MarginScreen("4a", "Graph map: whole semester", milestone: "M9") {
            AnyView(WorkspaceView(env: .fixture(), start: .graph))
        },
        MarginScreen("screens/1e", "Grades across the semester", milestone: "M11") { AnyView(WorkspaceView(env: .fixture(), start: .grades)) },
        MarginScreen("screens/1b", "Search results with filters", milestone: "M11") { AnyView(WorkspaceView(env: .fixture(), start: .search("membrane"))) },
        MarginScreen("screens/1f", "Past semesters", milestone: "M11") { AnyView(WorkspaceView(env: .fixture(), start: .archive)) },
        MarginScreen("screens/1g", "Settings window: Profile", milestone: "M11") {
            let w = Workspace(env: .fixture())
            return AnyView(SettingsView(model: w.settingsModel(), inWindow: true).environment(w))
        },
        MarginScreen("menus/3", "Tooltips and hover cards (3a–3h)", milestone: "M10d") { AnyView(MenusSheet()) },
        MarginScreen("course-icons", "Course icons: generator (proposal)", milestone: "M3") { AnyView(CourseIconSheet()) },
        MarginScreen("account", "Account popup (Account v3 1a, 1b)", milestone: "M11") { AnyView(AccountSheet()) },
        MarginScreen("settings-vault", "Settings › Vault and files (Account v3 2b)", milestone: "M11") {
            let w = Workspace(env: .fixture())
            w.settingsModel().section = .vault
            return AnyView(SettingsView(model: w.settingsModel(), inWindow: true).environment(w))
        },
        MarginScreen("course-style", "Course colour, icon or emoji picker", milestone: "M10") { AnyView(CourseStyleSheet()) },
    ]

    public static func screen(id: String) -> MarginScreen? { all.first { $0.id == id } }

    /// `--screen <id>` from the process arguments.
    public static func requestedID(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let i = arguments.firstIndex(of: "--screen"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}

/// Debug window listing every screen by mockup ID; selecting one shows it at 1240×820.
public struct ScreenGallery: View {
    @State private var selection: String?

    public init(initial: String? = nil) {
        _selection = State(initialValue: initial ?? MarginScreens.all.first?.id)
    }

    public var body: some View {
        NavigationSplitView {
            List(MarginScreens.all, selection: $selection) { screen in
                HStack(spacing: 8) {
                    Text(screen.id)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MarginColor.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(screen.title).marginFont(MarginTextSize.sm).lineLimit(1)
                        Text(screen.milestone).marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                    }
                }
                .tag(screen.id)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let id = selection, let screen = MarginScreens.screen(id: id) {
                ScrollView([.horizontal, .vertical]) {
                    screen.view()
                        .frame(width: MarginScreens.size.width, height: MarginScreens.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: MarginRadius.window))
                        .overlay {
                            RoundedRectangle(cornerRadius: MarginRadius.window).strokeBorder(Color(hex: 0xD5D7DD))
                        }
                        .marginShadow(.card)
                        .padding(40)
                }
                .background(MarginColor.canvas)
            } else {
                Text("Select a screen").foregroundStyle(MarginColor.textTertiary)
            }
        }
    }
}

/// Gallery: a course opened on one of its pages.
struct CoursePageScreen: View {
    @State private var workspace: Workspace

    init(page: CourseDetailModel.Page) {
        let w = Workspace(env: .fixture(), start: .course("bio"))
        w.courseModel("bio").page = page
        _workspace = State(initialValue: w)
    }

    var body: some View { WorkspaceView(workspace: workspace) }
}

/// Gallery: Lecture 8 in one editor mode.
struct EditorModeScreen: View {
    @State private var workspace: Workspace

    init(mode: EditorMode) {
        let w = Workspace(env: .fixture(), start: .note("bio/lecture-8"))
        w.editorModel(.note("bio/lecture-8")).setMode(mode)
        _workspace = State(initialValue: w)
    }

    var body: some View { WorkspaceView(workspace: workspace) }
}

/// Gallery: quick entry open with the mockup's sentence.
struct CaptureScreen: View {
    @State private var workspace: Workspace

    init() {
        let w = Workspace(env: .fixture(), start: .inbox)
        w.capture.open(prefill: "Read ch. 6 before wed for bio #reading")
        _workspace = State(initialValue: w)
    }

    var body: some View { WorkspaceView(workspace: workspace) }
}


/// Gallery `3a-lists`: a lecture note like a real one (headings, nested lists, footnotes).
private struct ListsSampleScreen: View {
    @State private var workspace = Workspace(env: .fixture())
    @State private var ready = false

    var body: some View {
        Group {
            if ready { WorkspaceView(workspace: workspace) } else { Color.white }
        }
        .task {
            let text = """
            # Milníky Historie 1

            ## Důsledky Lisabonské smlouvy:[^3]

            > [!warning] Na zkoušku
            > Umět **tři pilíře** a jejich zrušení.

            > [!tip]
            > Dočíst kapitolu 2 do pátku.

            > Evropa nebude vytvořena naráz. — R. Schuman

            ![Membrána|320](bilayer-diagram.png)

            | Transport | Energie | Příklad |
            | --- | --- | --- |
            | Pasivní | žádná | ==osmóza== |
            | Aktivní | ATP | Na⁺/K⁺ pumpa |

            ## Integrace jako souboj koncepcí

            ### Mezivládní [^1]
            - Intenzivní spolupráce, která zachovává atributy suverenity
            - státy jsou nedotknutelné
            - právo veta

            ### Nadnárodní [^2]
            - Odevzdání suverenity zemí ve prospěch nezávislé autority, které se dobrovolně podřizují všechny členské státy
            - rovnost členů
            \t- rozhoduje se většinou
            \t- kontrola a sankce
            - [ ] Dočíst kapitolu 2 @Fri

            Hlavní nástroj integrace je **evropské právo**.

            [^1]: Hlavní aktéři jsou státy.
            """
            if let note = try? await workspace.env.notes.open(id: "bio/lecture-8") {
                _ = try? await workspace.env.notes.save(id: note.id, text: text, actor: .user, baseVersion: note.version,
                                                         dryRun: false, idempotencyKey: nil)
            }
            workspace.open(.note("bio/lecture-8"), title: "Milníky Historie 1")
            ready = true
        }
    }
}
