import MarginCore
import Observation
import SwiftUI

/// Quick capture (5a, M8): one line parsed live into course, date, tags and a lecture note to
/// attach to; ⏎ saves to the course (or the attached note), ⌘⏎ to the Inbox.
@MainActor @Observable
public final class CaptureModel {
    public var isOpen = false
    public var text = "" { didSet { reparse() } }
    /// Task or Note (the segmented control; a `note:` prefix also switches it).
    public var kind: InboxKind = .task
    public private(set) var parsed = ParsedCapture(draft: CaptureDraft(text: ""))
    /// Chips the user removed (course, date, attachment) stay off for this entry.
    public var dropped: Set<CaptureSpanKind> = []
    public private(set) var saving = false
    public var error: String?

    private let env: AppEnvironment
    private var courses: [Course] = []
    private var notes: [NoteSummary] = []
    /// After a save (the workspace refreshes Inbox, Today…).
    public var onSaved: ((ChangeSet, Bool) -> Void)?

    public init(env: AppEnvironment) { self.env = env }

    public func open(prefill: String = "") {
        text = prefill
        kind = .task
        dropped = []
        error = nil
        isOpen = true
        Task { await prepare() }
    }

    public func close() { isOpen = false }

    /// Courses and lecture notes for the parser (course names, aliases, „for lecture 9“).
    public func prepare() async {
        courses = (try? await env.courses.courses(query: nil)) ?? []
        var all: [NoteSummary] = []
        for c in courses { all += (try? await env.notes.notes(course: c.id)) ?? [] }
        notes = all
        reparse()
    }

    private func reparse() {
        let parser = QuickCaptureParser(courses: courses, clock: env.clock, notes: notes)
        parsed = parser.parse(text)
        if parsed.draft.kind != .task && parsed.spans.contains(where: { $0.kind == .kindPrefix }) { kind = parsed.draft.kind }
    }

    /// The draft that will be saved, after removed chips and the Task/Note switch.
    public var draft: CaptureDraft {
        var d = parsed.draft
        d.kind = kind
        if dropped.contains(.course) { d.course = nil }
        if dropped.contains(.date) { d.due = nil }
        if dropped.contains(.attachment) { d.attachTo = nil }
        if dropped.contains(.tag) { d.tags = [] }
        return d
    }

    public var course: Course? { draft.course.flatMap { id in courses.first { $0.id == id } } }
    public var attachment: NoteSummary? { draft.attachTo.flatMap { id in notes.first { $0.id == id } } }

    /// „Add to Cell Biology ↵“, „Add to Lecture 9 ↵“, „Add to Inbox ↵“.
    public var primaryTitle: String {
        if let n = attachment { return "Add to \(CourseDetailModel.split(n).0) ↵" }
        if let c = course { return "Add to \(c.name) ↵" }
        return "Add to Inbox ↵"
    }

    /// ⏎: to the course / attached note; ⌘⏎ (`toInbox`): to the Inbox whatever was parsed.
    public func save(toInbox: Bool = false) async {
        var d = draft
        guard !d.text.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Type something first"; return }
        if toInbox { d.course = nil; d.attachTo = nil }
        saving = true
        defer { saving = false }
        do {
            let change = try await env.capture.commit(d, actor: .user, dryRun: false, idempotencyKey: nil)
            onSaved?(change, d.course == nil && d.attachTo == nil)
            text = ""
            isOpen = false
        } catch {
            self.error = Workspace.describe(error)
        }
    }

    /// Text with the detected parts marked for the input line (course and date colours, tags grey).
    public var highlighted: AttributedString {
        var out = AttributedString(text)
        for span in parsed.spans {
            guard let r = span.range(in: text),
                  let lo = AttributedString.Index(r.lowerBound, within: out),
                  let hi = AttributedString.Index(r.upperBound, within: out) else { continue }
            let range = lo..<hi
            switch span.kind {
            case .course:
                if let c = course, !dropped.contains(.course) {
                    out[range].backgroundColor = Color(hexString: c.style.background)
                    out[range].foregroundColor = Color(hexString: c.style.foreground)
                }
            case .date:
                if !dropped.contains(.date) {
                    out[range].backgroundColor = MarginColor.accentSoft
                    out[range].foregroundColor = MarginColor.accentText
                }
            case .tag, .kindPrefix:
                out[range].foregroundColor = MarginColor.textSecondary
            case .attachment, .url:
                out[range].foregroundColor = MarginColor.accentText
            }
        }
        return out
    }
}
