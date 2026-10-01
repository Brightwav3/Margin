import AppKit
import MarginCore
import MarginPlatform
import MarginUI
import Observation
import SwiftUI

/// The running app: which vault is open, the window's workspace, the global quick capture.
@MainActor @Observable
final class AppState {
    enum Phase {
        case welcome
        case opening(URL)
        case ready(Workspace)
        case failed(String)
    }

    var phase: Phase = .welcome
    var progress: IndexProgress?
    private var env: AppEnvironment?
    /// Bumped on every opened vault, so listeners of an old one stop.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let hotkeys = CarbonGlobalHotkeyService()
    @ObservationIgnored private var panel: CapturePanel?

    var workspace: Workspace? { if case .ready(let w) = phase { w } else { nil } }

    /// Reopens the remembered vault; otherwise shows the welcome screen.
    func start() {
        // `--sample`: straight into sample data (UI tests, demos); never touches the vault.
        if ProcessInfo.processInfo.arguments.contains("--sample") { openSample(); return }
        if let url = VaultLocation.restore() { open(url) } else { phase = .welcome }
        registerHotkey()
    }

    func chooseVault() {
        guard let url = VaultLocation.choose() else { return }
        open(url)
    }

    func openSample() {
        let env = AppEnvironment.fixture()
        ready(env, vault: nil)
    }

    func open(_ url: URL) {
        phase = .opening(url)
        progress = nil
        Task { @MainActor in
            do {
                let env = try await AppEnvironment.vault(at: url, reminderCenter: UserNotificationCenter(),
                                                         progress: { [weak self] p in
                                                             Task { @MainActor in self?.progress = p }
                                                         })
                ready(env, vault: url)
            } catch {
                phase = .failed("Margin could not open \(url.path(percentEncoded: false)): \(error)")
            }
        }
    }

    private func ready(_ env: AppEnvironment, vault: URL?) {
        let old = self.env
        self.env = env
        Task { await old?.shutdown() }
        let workspace = Workspace(env: env, vaultURL: vault)
        if vault != nil { workspace.vaults = self }
        workspace.applySettings()
        workspace.applyStartupPlace()
        phase = .ready(workspace)
        Task { await scheduleReminders(env) }
        generation += 1
        let current = generation
        Task { await followQuickCaptureSetting(env, generation: current) }
    }

    /// Settings › General › Quick capture from any app turns the global ⇧⌘Space on and off.
    private func followQuickCaptureSetting(_ env: AppEnvironment, generation: Int) async {
        func apply() async {
            if await env.settings.get(Settings.globalQuickCapture) { registerHotkey() } else { hotkeys.unregister(.quickCapture) }
        }
        await apply()
        for await change in env.settings.changes where change.key == Settings.globalQuickCapture.key {
            guard self.generation == generation else { return }
            await apply()
        }
    }

    /// Class notifications for this week (and the next) when allowed (1i, M10-18).
    private func scheduleReminders(_ env: AppEnvironment) async {
        guard await env.reminders.permission == .authorized,
              let semester = try? await env.semesters.current(),
              let week = env.clock.weekOfSemester(semester) else { return }
        _ = try? await env.reminders.schedule(for: week)
        _ = try? await env.reminders.schedule(for: week + 1)
    }

    func shutdown() async { await env?.shutdown() }

    // MARK: Quick capture from any app (⌘⇧Space, M8-02)

    private func registerHotkey() {
        try? hotkeys.register(.quickCapture) { [weak self] in
            Task { @MainActor in self?.showCapture() }
        }
    }

    func showCapture() {
        guard let workspace else { NSApp.activate(); return }
        // With the window in front, capture opens over it; from another app, in the floating panel.
        if NSApp.isActive, NSApp.keyWindow is CapturePanel == false {
            workspace.capture.open()
            return
        }
        if panel == nil {
            let model = CaptureModel(env: workspace.env)
            model.onSaved = { [weak workspace] _, toInbox in
                Task { await workspace?.refreshAfterWrite() }
                workspace?.show(toInbox ? "Added to Inbox" : "Saved")
            }
            panel = CapturePanel(model: model)
        }
        panel?.present()
    }
}

// MARK: Vaults (account popup › Switch vault, Manage vaults)

extension AppState: VaultSwitching {
    func recentVaults() -> [VaultChoice] {
        let current = workspace?.vaultURL?.path
        return VaultLocation.recents().map { VaultChoice(name: $0.name, path: $0.path, isCurrent: $0.path == current) }
            .sorted { $0.isCurrent && !$1.isCurrent }
    }

    func open(_ vault: VaultChoice) {
        guard let recent = VaultLocation.recents().first(where: { $0.path == vault.path }) else { return }
        guard let url = VaultLocation.resolve(recent) else {
            workspace?.show("“\(vault.name)” is no longer at \(vault.path)", icon: "error", error: true)
            return
        }
        VaultLocation.remember(url)
        open(url)
    }

    func openFolder() { chooseVault() }

    func createVault() {
        guard let url = VaultLocation.createNew() else { return }
        open(url)
    }

    func removeFromList(_ vault: VaultChoice) {
        guard let recent = VaultLocation.recents().first(where: { $0.path == vault.path }) else { return }
        VaultLocation.removeFromList(recent)
    }

    func revealVault() {
        if let url = workspace?.vaultURL { VaultLocation.reveal(url) }
    }
}

/// Floating panel for quick capture over other apps: does not activate Margin, centred on the
/// screen with the pointer, closes on save, ⎋ or losing focus.
final class CapturePanel: NSPanel {
    private let model: CaptureModel
    private var host: NSView?
    private let container = NSView()

    init(model: CaptureModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 660, height: 260),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        let host = NSHostingView(rootView: CapturePanelContent(model: model) { [weak self] in self?.orderOut(nil) })
        // Sized by hand in `present()`; sizing options would let the hosting view drive the window's
        // size limits from inside a layout pass.
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        contentView = container
        self.host = host
    }

    override var canBecomeKey: Bool { true }

    func present() {
        model.open()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        // Room below for chips and an error line that appear while typing (the panel is transparent).
        // Measured and placed while out of the window: a hosting view resized inside a panel can
        // re-enter constraint updates until AppKit throws.
        host?.removeFromSuperview()
        var size = host?.fittingSize ?? NSSize(width: 660, height: 260)
        size.height += 90
        if let frame = screen?.visibleFrame {
            setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.28 - size.height,
                            width: size.width, height: size.height), display: false)
        }
        if let host {
            host.frame = NSRect(origin: .zero, size: size)
            container.addSubview(host)
        }
        makeKeyAndOrderFront(nil)
    }

    override func resignKey() {
        super.resignKey()
        model.close()
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        model.close()
        orderOut(nil)
    }
}

private struct CapturePanelContent: View {
    @Bindable var model: CaptureModel
    let dismiss: () -> Void

    var body: some View {
        QuickCaptureView(model: model, showsHint: false)
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .onChange(of: model.isOpen) { _, open in if !open { dismiss() } }
    }
}

/// Root of the main window.
struct AppRootView: View {
    let state: AppState

    var body: some View {
        Group {
            switch state.phase {
            case .welcome:
                WelcomeView(state: state)
            case .opening(let url):
                OpeningView(url: url, progress: state.progress)
            case .ready(let workspace):
                WorkspaceView(workspace: workspace)
                    .id(ObjectIdentifier(workspace))
            case .failed(let message):
                VStack(spacing: 14) {
                    Text("Could not open the vault").font(.margin(20, .semibold))
                    Text(message).font(.margin(13)).foregroundStyle(MarginColor.textSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 480)
                    HStack {
                        MarginButton("Choose another folder…", kind: .primary) { state.chooseVault() }
                        MarginButton("Use sample data") { state.openSample() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MarginColor.surface)
            }
        }
        .frame(minWidth: 820, idealWidth: MarginScreens.size.width, maxWidth: .infinity,
               minHeight: 560, idealHeight: MarginScreens.size.height, maxHeight: .infinity)
    }
}

private struct WelcomeView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 18) {
            CourseTile(icon: "graduation-cap", background: MarginColor.accentSoft, foreground: MarginColor.accentText, size: 64)
            Text("Margin").font(.margin(34, .bold))
            Text("Notes and tasks for your semester, kept as Markdown files in a folder you choose.")
                .font(.margin(15)).foregroundStyle(MarginColor.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 10) {
                MarginButton("Choose vault folder…", icon: "folder", kind: .primary) { state.chooseVault() }
                MarginButton("Explore sample data") { state.openSample() }
            }
            Text("Suggested: Documents › Margin. An existing Obsidian vault works too.")
                .font(.margin(12)).foregroundStyle(MarginColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MarginColor.sidebar)
    }
}

private struct OpeningView: View {
    let url: URL
    let progress: IndexProgress?

    var body: some View {
        VStack(spacing: 14) {
            if let p = progress, p.filesTotal > 0 {
                ProgressView(value: Double(p.filesDone), total: Double(p.filesTotal)).frame(width: 280)
                Text("Indexing \(p.filesDone) of \(p.filesTotal) notes").font(.margin(14)).foregroundStyle(MarginColor.textSecondary)
            } else {
                ProgressView()
                Text("Opening \(url.lastPathComponent)…").font(.margin(14)).foregroundStyle(MarginColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MarginColor.surface)
    }
}

/// The menu bar (Margin Menu Bar 1a–1k, M10-34): every command with its shortcut. Items act on the
/// active tab and editor and are disabled when there is nothing to act on; Agent waits for MA3.
struct MarginCommands: Commands {
    let state: AppState

    private var w: Workspace? { state.workspace }
    private var editing: Bool { w?.canEditText == true }
    private var note: Bool { w?.currentNote != nil }

    var body: some Commands {
        // 1a Margin
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { w?.run(command: "settings") }.keyboardShortcut(",")
            Button("Check for updates…") {}.disabled(true)
        }

        // 1b File
        CommandGroup(replacing: .newItem) {
            Button("New note") { w?.run(command: "new-note") }.keyboardShortcut("n").disabled(w == nil)
            Button("New lecture note") { w?.newLectureNote() }.keyboardShortcut("n", modifiers: [.control, .command]).disabled(w == nil)
            Button("New folder") {}.keyboardShortcut("n", modifiers: [.shift, .command]).disabled(true)
            Button("New course…") { w?.run(command: "new-course") }.disabled(w == nil)
            Button("New semester…") { w?.dialog = .newSemester }.disabled(w == nil)
            Button("Quick capture") { state.showCapture() }.keyboardShortcut(.space, modifiers: [.shift, .command])
            Divider()
            Button("Open vault…") { state.chooseVault() }.keyboardShortcut("o", modifiers: [.shift, .command])
            Menu("Open recent") {
                ForEach(w?.recentNotes ?? [], id: \.id) { r in Button(r.title) { w?.openRecent(r.id, title: r.title) } }
                if w?.recentNotes.isEmpty ?? true { Button("No recent notes") {}.disabled(true) }
                Divider()
                Button("Use sample data") { state.openSample() }
            }
            Divider()
            Menu("Import") {
                Button("Syllabus…") { w?.run(command: "syllabus") }.disabled(w?.courses.cards.isEmpty ?? true)
                Button("Markdown files…") { w?.importMarkdownFiles() }.disabled(w?.courses.cards.isEmpty ?? true)
            }
            Menu("Export") {
                Button("PDF…") { w?.shareCurrentNote() }.disabled(!note)
                Button("Markdown…") { w?.shareCurrentNote() }.disabled(!note)
            }
            Button("Share…") { w?.shareCurrentNote() }.disabled(!note)
            Divider()
            Button("Close tab") { w?.closeActiveTab() }.keyboardShortcut("w").disabled(w?.shell.tabs.isEmpty ?? true)
            Button("Close window") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w", modifiers: [.shift, .command])
            Divider()
            Button("Move to trash") { w?.deleteCurrentNote() }.keyboardShortcut(.delete, modifiers: .command).disabled(!note)
        }

        // 1c Edit (Undo, Cut, Copy, Paste, Select all, Dictation and Emoji come from the system)
        CommandGroup(after: .pasteboard) {
            Button("Copy as Markdown") { w?.copyAsMarkdown() }.keyboardShortcut("c", modifiers: [.option, .command]).disabled(!(w?.hasEditor ?? false))
            Button("Paste as plain text") { w?.pasteAsPlainText() }.keyboardShortcut("v", modifiers: [.shift, .command]).disabled(!editing)
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find in note") { w?.findInNote(replace: false) }.keyboardShortcut("f").disabled(!(w?.hasEditor ?? false))
            Button("Find and replace") { w?.findInNote(replace: true) }.keyboardShortcut("f", modifiers: [.option, .command]).disabled(!editing)
            Button("Search vault") { w?.open(.search("")) }.keyboardShortcut("f", modifiers: [.shift, .command]).disabled(w == nil)
        }

        // 1d View
        CommandGroup(replacing: .sidebar) {
            Toggle("Reading view", isOn: Binding(get: { w?.isReading ?? false }, set: { _ in w?.toggleReading() }))
                .keyboardShortcut("e").disabled(!(w?.hasEditor ?? false))
            Toggle("Source mode", isOn: Binding(get: { w?.isSource ?? false }, set: { _ in w?.toggleSource() }))
                .keyboardShortcut("e", modifiers: [.shift, .command]).disabled(!(w?.hasEditor ?? false))
            Divider()
            Toggle("Sidebar", isOn: Binding(get: { !(w?.shell.sidebarCollapsed ?? true) }, set: { _ in w?.shell.toggleSidebar() }))
                .keyboardShortcut("\\").disabled(w == nil)
            Toggle("Right panel", isOn: Binding(get: { w?.shell.inspectorOpen ?? false }, set: { _ in w?.shell.toggleInspector() }))
                .keyboardShortcut("\\", modifiers: [.option, .command]).disabled(w == nil)
            Toggle("Properties", isOn: Binding(get: { w?.showsProperties ?? true }, set: { _ in w?.toggleProperties() })).disabled(w == nil)
            Toggle("Readable line length", isOn: Binding(get: { w?.readableLineLength ?? true }, set: { _ in w?.toggleReadableLineLength() })).disabled(w == nil)
            Toggle("Line numbers", isOn: .constant(false)).disabled(true)
            Divider()
            Button("Split right") {}.disabled(true)
            Button("Split down") {}.disabled(true)
            Divider()
            Button("Zoom in") { w?.zoomText(1) }.keyboardShortcut("+").disabled(w == nil)
            Button("Zoom out") { w?.zoomText(-1) }.keyboardShortcut("-").disabled(w == nil)
            Button("Actual size") { w?.zoomText(0) }.keyboardShortcut("0").disabled(w == nil)
        }

        // 1e Insert
        CommandMenu("Insert") {
            Group {
                Button("Link to note") { w?.insert(.link) }.keyboardShortcut("k", modifiers: [.shift, .command])
                Button("Task") { w?.insert(.task) }.keyboardShortcut("l")
                Button("Table") { w?.insert(.table) }.keyboardShortcut("t", modifiers: [.option, .command])
                Button("Formula") { w?.insert(.formula) }.keyboardShortcut("m", modifiers: [.option, .command])
                Button("Flashcard") {}.keyboardShortcut("l", modifiers: [.shift, .command]).disabled(true)
                Button("Image or file…") {}.keyboardShortcut("i", modifiers: [.shift, .command]).disabled(true)
                Button("Date and time") { w?.insert(.date) }.keyboardShortcut("d", modifiers: [.shift, .command])
                Divider()
                Button("Callout") { w?.insert(.callout) }
                Button("Code block") { w?.insert(.code) }
                Button("Footnote") { w?.insert(.footnote) }
                Button("Divider") { w?.insert(.divider) }
                Divider()
                Button("From template…") {}.disabled(true)
            }
            .disabled(!editing)
        }

        // 1f Format
        CommandMenu("Format") {
            Group {
                Button("Bold") { w?.format(.bold) }.keyboardShortcut("b")
                Button("Italic") { w?.format(.italic) }.keyboardShortcut("i")
                Button("Underline") { w?.format(.underline) }.keyboardShortcut("u")
                Button("Strikethrough") { w?.format(.strike) }.keyboardShortcut("x", modifiers: [.shift, .command])
                Button("Highlight") { w?.format(.highlight) }.keyboardShortcut("h", modifiers: [.shift, .command])
                Button("Inline code") { w?.format(.code) }.keyboardShortcut("`")
                Divider()
                Menu("Heading") {
                    Button("Heading 1") { w?.format(.heading1) }.keyboardShortcut("1", modifiers: [.option, .command])
                    Button("Heading 2") { w?.format(.heading2) }.keyboardShortcut("2", modifiers: [.option, .command])
                    Button("Heading 3") { w?.format(.heading3) }.keyboardShortcut("3", modifiers: [.option, .command])
                }
                Button("Paragraph") { w?.format(.paragraph) }.keyboardShortcut("0", modifiers: [.option, .command])
                Button("Quote") { w?.format(.quote) }.keyboardShortcut(".", modifiers: [.shift, .command])
                Button("Bulleted list") { w?.format(.bullets) }.keyboardShortcut("8", modifiers: [.shift, .command])
                Button("Numbered list") { w?.format(.numbers) }.keyboardShortcut("7", modifiers: [.shift, .command])
                Button("Checklist") { w?.format(.checklist) }.keyboardShortcut("9", modifiers: [.shift, .command])
                Divider()
                Button("Indent") { w?.indentSelection() }.keyboardShortcut("]")
                Button("Outdent") { w?.outdentSelection() }.keyboardShortcut("[")
                Divider()
                Button("Clear formatting") { w?.clearFormatting() }.keyboardShortcut("\\", modifiers: [.control, .command])
            }
            .disabled(!editing)
        }

        // 1g Note
        CommandMenu("Note") {
            Button("Link to session…") {}.disabled(true)
            Button("Add to revision") { w?.addCurrentNoteToRevision() }.disabled(!note)
            Button("Make flashcards from note") {}.disabled(true)
            Divider()
            Button("Add property") { w?.addPropertyToCurrentNote() }.keyboardShortcut(";").disabled(!note)
            Button("Rename…") {}.disabled(true)
            Button("Move to…") { w?.moveCurrentNote() }.keyboardShortcut("m", modifiers: [.shift, .command]).disabled(!note)
            Button("Merge with…") {}.disabled(true)
            Button("Bookmark") {}.keyboardShortcut("d").disabled(true)
            Divider()
            Button("Backlinks") { w?.showBacklinks() }.disabled(!note)
            Button("Version history") { w?.historyOfCurrentNote() }.disabled(!note)
            Button("Reveal in Finder") {}.keyboardShortcut("r", modifiers: [.option, .command]).disabled(true)
        }

        // 1h Go
        CommandMenu("Go") {
            Group {
                Button("Today") { w?.run(command: "today") }.keyboardShortcut("1")
                Button("Upcoming") { w?.run(command: "upcoming") }.keyboardShortcut("2")
                Button("Inbox") { w?.run(command: "inbox") }.keyboardShortcut("3")
                Button("Schedule") { w?.run(command: "timetable") }.keyboardShortcut("4")
                Button("Flashcard review") {}.keyboardShortcut("5").disabled(true)
                Divider()
                Button("Command palette") { w?.dialog = .palette }.keyboardShortcut("k")
                Button("Quick open…") { w?.dialog = .palette }.keyboardShortcut("o")
                Divider()
                Button("Back") { w?.goBack() }.keyboardShortcut(.leftArrow, modifiers: [.option, .command]).disabled(!(w?.canGoBack ?? false))
                Button("Forward") { w?.goForward() }.keyboardShortcut(.rightArrow, modifiers: [.option, .command]).disabled(!(w?.canGoForward ?? false))
                Divider()
                Button("Next lecture") { w?.openAdjacentLecture(1) }.keyboardShortcut(.rightArrow, modifiers: [.control, .command])
                    .disabled(w?.currentCourse == nil)
                Button("Previous lecture") { w?.openAdjacentLecture(-1) }.keyboardShortcut(.leftArrow, modifiers: [.control, .command])
                    .disabled(w?.currentCourse == nil)
                Menu("Course") {
                    Button("All courses") { w?.run(command: "courses") }
                    Divider()
                    ForEach(w?.courses.cards ?? []) { card in Button(card.course.name) { w?.open(course: card.course) } }
                }
                Button("Graph") { w?.run(command: "graph") }
                Button("Grades") { w?.run(command: "grades") }
            }
            .disabled(w == nil)
        }

        // 1i Agent — greyed out until the in-app agent (MA3).
        CommandMenu("Agent") {
            Group {
                Button("Ask agent…") {}.keyboardShortcut("j")
                Divider()
                Button("Explain selection") {}
                Button("Summarise note") {}
                Button("Suggest links") {}
                Button("Make flashcards") {}
                Button("Quiz me on this note") {}
                Divider()
                Button("Agent panel") {}.keyboardShortcut("j", modifiers: [.option, .command])
                Divider()
                Button("Agent settings…") {}
            }
            .disabled(true)
        }

        // 1j Window (Minimise, Zoom, Bring all to front and the window list come from the system)
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Next tab") { w?.nextTab() }.keyboardShortcut(.tab, modifiers: .control)
            Button("Previous tab") { w?.previousTab() }.keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Pin tab") {}.disabled(true)
        }

        // 1k Help (the system adds the search field that finds any command)
        CommandGroup(replacing: .help) {
            Button("Margin help") { w?.dialog = .help(.markdown) }
            Button("Keyboard shortcuts") { w?.dialog = .help(.shortcuts) }.keyboardShortcut("/")
            Button("Markdown guide") { w?.dialog = .help(.markdown) }
            Button("What’s new") { w?.dialog = .help(.whatsNew) }
            Divider()
            Button("Send feedback…") {}.disabled(true)
            Button("Report a problem…") {}.disabled(true)
        }
    }
}
