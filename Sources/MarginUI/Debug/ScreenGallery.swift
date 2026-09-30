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
            AnyView(CoursesScreen(env: .fixture(), mode: .grid))
        },
        MarginScreen("1b", "Courses home: timetable", milestone: "M3") {
            AnyView(CoursesScreen(env: .fixture(), mode: .timetable))
        },
        MarginScreen("course-icons", "Course icons: generator (proposal)", milestone: "M3") { AnyView(CourseIconSheet()) },
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
