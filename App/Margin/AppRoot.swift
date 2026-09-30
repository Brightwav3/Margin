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
        phase = .ready(Workspace(env: env, vaultURL: vault))
        Task { await scheduleReminders(env) }
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

/// Floating panel for quick capture over other apps: does not activate Margin, centred on the
/// screen with the pointer, closes on save, ⎋ or losing focus.
final class CapturePanel: NSPanel {
    private let model: CaptureModel
    private var host: NSView?

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
        contentView = host
        self.host = host
    }

    override var canBecomeKey: Bool { true }

    func present() {
        model.open()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        // Room below for chips and an error line that appear while typing (the panel is transparent).
        var size = host?.fittingSize ?? NSSize(width: 660, height: 260)
        size.height += 90
        if let frame = screen?.visibleFrame {
            setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.28 - size.height,
                            width: size.width, height: size.height), display: true)
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

/// Menu bar commands (File, View) wired to the open workspace.
struct MarginCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { state.workspace?.run(command: "new-note") }.keyboardShortcut("n")
            Button("New Course…") { state.workspace?.run(command: "new-course") }
            Button("Quick Capture") { state.showCapture() }.keyboardShortcut(.space, modifiers: [.command, .shift])
            Divider()
            Button("Open Vault…") { state.chooseVault() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Use Sample Data") { state.openSample() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { state.workspace?.run(command: "settings") }.keyboardShortcut(",")
        }
        CommandGroup(after: .textEditing) {
            Button("Command Palette") { state.workspace?.dialog = .palette }.keyboardShortcut("k")
            Button("Search All Notes") { state.workspace?.open(.search("")) }.keyboardShortcut("f", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            Button("Courses") { state.workspace?.run(command: "courses") }.keyboardShortcut("1")
            Button("Today") { state.workspace?.run(command: "today") }.keyboardShortcut("2")
            Button("Upcoming") { state.workspace?.run(command: "upcoming") }.keyboardShortcut("3")
            Button("Inbox") { state.workspace?.run(command: "inbox") }.keyboardShortcut("4")
            Button("Timetable") { state.workspace?.run(command: "timetable") }
            Button("Graph") { state.workspace?.run(command: "graph") }
            Button("Grades") { state.workspace?.run(command: "grades") }
        }
    }
}
