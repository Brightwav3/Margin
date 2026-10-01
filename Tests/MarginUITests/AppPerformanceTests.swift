import AppKit
import MarginCore
import SwiftUI
import Testing
@testable import MarginUI

/// M12-02.U: the UI budgets of `04-engineering-rules.md` §5 on a real vault of 1000 notes —
/// first screen, memory, graph frames and the quick capture overlay. Debug builds get the same
/// headroom as the core perf suites (`perfBudget` there); the numbers are printed for the record.
@MainActor @Suite(.serialized) struct AppPerformanceTests {
    private static let debugFactor: Double = {
        #if DEBUG
        3
        #else
        1
        #endif
    }()

    @Test func budgetsOnAThousandNoteVault() async throws {
        let scratch = try await AppEnvironment.scratchVault()
        let url = scratch.url
        defer { AppEnvironment.removeScratchVault(at: url) }
        try await fill(scratch.env, courses: 10, notesPerCourse: 100)
        await scratch.env.shutdown()

        // Cold start: open the folder and draw the courses screen.
        let clock = ContinuousClock()
        var env: AppEnvironment?
        let start = try await clock.measure {
            env = try await AppEnvironment.vault(at: url)
            let workspace = Workspace(env: env!, vaultURL: url)
            await workspace.courses.load()
            render(WorkspaceView(workspace: workspace))
        }
        let opened = try #require(env)
        defer { Task { await opened.shutdown() } }
        print("PERF cold start with 1000 notes: \(start)")
        #expect(start < .milliseconds(1000 * Self.debugFactor), "cold start \(start)")

        // Memory after the start.
        let resident = residentMegabytes()
        print("PERF resident memory: \(resident) MB")
        #expect(resident < 250 * Self.debugFactor, "resident \(resident) MB")

        // Graph: a frame of the semester map (1000 notes, ≥ 500 nodes) within 1/60 s. Only the graph
        // view is drawn, after its layout settled and a warm-up frame.
        let graph = Workspace(env: opened, vaultURL: url)
        let model = graph.graphModel()
        await model.load()
        print("PERF graph nodes: \(model.positions.count)")
        #expect(model.positions.count >= 500)
        let host = host(GraphView(model: model).environment(graph))
        try await Task.sleep(for: .seconds(1.5))
        draw(host)
        var frames: [Duration] = []
        for i in 0..<30 {
            // Each frame pans the map a little, as dragging does.
            frames.append(clock.measure {
                model.offset = CGSize(width: CGFloat(i % 2 == 0 ? 3 : -3), height: 0)
                draw(host)
            })
        }
        let median = frames.sorted()[frames.count / 2]
        print("PERF graph frame median: \(median)")
        #expect(median < .microseconds(Int64(16_667 * Self.debugFactor)), "graph frame \(median)")

        // Quick capture: from the shortcut to a drawn overlay, once fonts and icons are loaded (the
        // panel is made at launch; the shortcut only shows it).
        render(QuickCaptureView(model: CaptureModel(env: opened)).frame(width: 640))
        let capture = clock.measure {
            let model = CaptureModel(env: opened)
            model.open()
            render(QuickCaptureView(model: model).frame(width: 640, height: 260))
        }
        print("PERF quick capture overlay: \(capture)")
        #expect(capture < .milliseconds(Int64(120 * Self.debugFactor)), "quick capture \(capture)")
    }

    // MARK: Helpers

    /// `courses` courses with `notesPerCourse` notes each; every note links to the next two.
    private func fill(_ env: AppEnvironment, courses: Int, notesPerCourse: Int) async throws {
        _ = try await env.semesters.create(NewSemester(name: "Podzim 2026", start: LocalDate(year: 2026, month: 9, day: 14)!,
                                                       end: LocalDate(year: 2026, month: 12, day: 20)!),
                                           actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
        let paragraph = String(repeating: "Membrány, osmóza a model tekuté mozaiky v buňce. ", count: 25)
        for c in 0..<courses {
            _ = try await env.courseWriter.create(NewCourse(name: "Course \(c)", semester: "podzim-2026", code: "C\(c)"),
                                                  actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let id = "course-\(c)"
            for n in 0..<notesPerCourse {
                let text = "# Note \(c)-\(n)\n\n\(paragraph)\n\n- [ ] Task \(n)\n\n[[Note \(c)-\(n + 1)]] [[Note \(c)-\(n + 2)]]\n"
                _ = try await env.notes.create(course: id, title: "Note \(c)-\(n)", kind: .lecture, text: text, actor: .user,
                                               baseVersion: nil, dryRun: false, idempotencyKey: nil)
            }
        }
    }

    private func host<V: View>(_ view: V) -> NSHostingView<AnyView> {
        let size = MarginScreens.size
        let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))   // off screen, but a real window
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func render<V: View>(_ view: V) {
        draw(host(view))
    }

    /// One frame as the window shows it: SwiftUI updates and draws, Core Animation commits (the
    /// GPU composites shadows and blur afterwards, as on screen). `cacheDisplay` would rasterise
    /// shadows on the CPU and measure something the app never does.
    private func draw(_ host: NSView) {
        host.needsDisplay = true
        host.window?.displayIfNeeded()
        CATransaction.flush()
    }

    private func residentMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }
}
