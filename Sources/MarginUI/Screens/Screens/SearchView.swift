import MarginCore
import Observation
import SwiftUI

/// Screens 1b Search results with filters (M11-03.U): course, kind, date range, tag; matches
/// highlighted in titles and snippets.
@MainActor @Observable
public final class SearchModel {
    public enum Range: String, CaseIterable, Sendable { case any, thisSemester, thisWeek }

    public var query: String { didSet { schedule() } }
    public var course: CourseID? { didSet { schedule() } }
    public var kind: NoteKind? { didSet { schedule() } }
    public var range: Range = .any { didSet { schedule() } }
    public var tag = "" { didSet { schedule() } }
    public private(set) var hits: [SearchHit] = []
    public private(set) var searched = false
    private var task: Task<Void, Never>?
    private let env: AppEnvironment

    public init(env: AppEnvironment, query: String = "") {
        self.env = env
        self.query = query
    }

    func filter(semester: Semester?) -> SearchFilter {
        let today = env.clock.today
        var from: LocalDate?, to: LocalDate?
        switch range {
        case .any: break
        case .thisSemester: from = semester?.start; to = semester?.end
        case .thisWeek: from = today.startOfWeek; to = today.startOfWeek.adding(days: 6)
        }
        let tags = tag.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty }
        return SearchFilter(course: course, kind: kind, from: from, to: to, tags: tags)
    }

    var semester: Semester?

    private func schedule() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            await self.run()
        }
    }

    public func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        let f = filter(semester: semester)
        guard !q.isEmpty || !f.restrictsNothing else { hits = []; searched = false; return }
        hits = (try? await env.search.search(query: q, filter: f)) ?? []
        searched = true
    }

    public var summary: String {
        let notes = hits.count
        let matches = hits.reduce(0) { $0 + max(1, $1.highlights.count) }
        return "\(matches) \(matches == 1 ? "match" : "matches") in \(notes) \(notes == 1 ? "note" : "notes")"
    }

    /// Text with the highlight ranges (UTF-16 offsets) marked.
    static func marked(_ text: String, _ ranges: [HighlightRange]) -> AttributedString {
        var out = AttributedString()
        let ns = text as NSString
        var at = 0
        for r in ranges.sorted(by: { $0.location < $1.location }) where r.location >= at && r.location + r.length <= ns.length {
            out += AttributedString(ns.substring(with: NSRange(location: at, length: r.location - at)))
            var hit = AttributedString(ns.substring(with: NSRange(location: r.location, length: r.length)))
            hit.backgroundColor = MarginColor.warningSoft
            hit.foregroundColor = MarginColor.ink
            out += hit
            at = r.location + r.length
        }
        if at < ns.length { out += AttributedString(ns.substring(from: at)) }
        return out
    }
}

struct SearchView: View {
    @Bindable var model: SearchModel
    @Environment(Workspace.self) private var workspace
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Icon("search", size: 22, color: MarginColor.textSecondary)
                    TextField("Search all notes", text: $model.query)
                        .textFieldStyle(.plain).marginFont(MarginTextSize.lg).focused($focused)
                    Text("⌘⇧F").marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                }
                .padding(.horizontal, 16).frame(height: 52)
                .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.md))
                .overlay { RoundedRectangle(cornerRadius: MarginRadius.md).strokeBorder(MarginColor.border) }
                filters
                if model.searched {
                    Text(model.summary).marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.hits) { hit in result(hit) }
                }
                if model.searched && model.hits.isEmpty {
                    EmptyState(icon: "search", title: "No matches", text: "Try fewer words or remove a filter.")
                }
            }
            .padding(.horizontal, 36).padding(.vertical, 28)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            model.semester = workspace.courses.semester
            focused = true
            Task { await model.run() }
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All courses") { model.course = nil }
                ForEach(workspace.courses.cards) { c in Button(c.course.name) { model.course = c.id } }
            } label: { OutlinedControl { Text(model.course.flatMap { workspace.courses.course(id: $0)?.name } ?? "All courses"); Icon("expand_more", size: 16) } }
                .controlMenu()
            Menu {
                Button("Any type") { model.kind = nil }
                ForEach(NoteKind.allCases, id: \.self) { k in Button(k.rawValue.capitalized) { model.kind = k } }
            } label: { OutlinedControl { Text(model.kind.map { $0.rawValue.capitalized } ?? "Any type"); Icon("expand_more", size: 16) } }
                .controlMenu()
            Menu {
                Button("Any time") { model.range = .any }
                Button("This semester") { model.range = .thisSemester }
                Button("This week") { model.range = .thisWeek }
            } label: {
                OutlinedControl {
                    Text(model.range == .any ? "Any time" : model.range == .thisSemester ? "This semester" : "This week")
                    Icon("expand_more", size: 16)
                }
            }
            .controlMenu()
            MarginField(placeholder: "#tag", text: $model.tag).frame(width: 140)
            Spacer()
        }
    }

    private func result(_ hit: SearchHit) -> some View {
        let course = hit.courseID.flatMap { workspace.courses.course(id: $0) }
        return Button { workspace.open(.note(hit.id), title: hit.title) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(SearchModel.marked(hit.title, hit.titleHighlights)).marginFont(MarginTextSize.md, .semibold)
                HStack(spacing: 6) {
                    if let course { Circle().fill(Color(hexString: course.style.dot)).frame(width: 7, height: 7); Text(course.name) }
                    if let d = hit.date { Text("· \(CourseDetailModel.day(d))") }
                    Text("· \(max(1, hit.highlights.count)) \(hit.highlights.count == 1 ? "match" : "matches")")
                }
                .marginFont(MarginTextSize.xs).foregroundStyle(MarginColor.textTertiary)
                Text(SearchModel.marked(hit.snippet, hit.highlights)).marginFont(MarginTextSize.base)
                    .foregroundStyle(MarginColor.textSecondary).lineLimit(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        .contextMenu {
            // 1q
            MenuItem("Open", "description") { workspace.open(.note(hit.id), title: hit.title) }
            MenuItem("Open in new tab", "open_in_new") { workspace.open(.note(hit.id), title: hit.title, newTab: true) }
            MenuItem("Open to the right", "vertical_split") {}.disabled(true)
            Divider()
            MenuItem("Copy link", "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[[\(hit.title)]]", forType: .string)
            }
            MenuItem("Reveal in sidebar", "my_location") {
                if let c = hit.courseID, let course = workspace.courses.course(id: c) {
                    workspace.open(course: course)
                    workspace.shell.sidebarPage = .notes
                    workspace.shell.sidebarCollapsed = false
                }
            }
        }
    }
}
