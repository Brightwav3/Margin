import MarginCore
import Observation
import SwiftUI

/// Screens 1b Search results with filters (M11-03.U): course, kind, date range, tag; matches
/// highlighted in titles and snippets.
@MainActor @Observable
public final class SearchModel {
    public enum Range: String, CaseIterable, Sendable { case any, thisSemester, thisWeek }

    public var query: String { didSet { schedule() } }
    /// 2h: several courses and kinds can be chosen; none means all.
    public var courses: Set<CourseID> = [] { didSet { schedule() } }
    public var kinds: Set<NoteKind> = [] { didSet { schedule() } }
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
        // One course or kind narrows the search itself; several are applied to the hits.
        let single = courses.count == 1 && kinds.count <= 1
        return SearchFilter(course: courses.count == 1 ? courses.first : nil, kind: kinds.count == 1 ? kinds.first : nil,
                            from: from, to: to, tags: tags, limit: single ? SearchFilter.defaultLimit : 500)
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
        guard !q.isEmpty || !f.restrictsNothing || !courses.isEmpty || !kinds.isEmpty else { hits = []; searched = false; return }
        let found = (try? await env.search.search(query: q, filter: f)) ?? []
        hits = Array(found.filter { hit in
            (courses.isEmpty || hit.courseID.map(courses.contains) == true) && (kinds.isEmpty || kinds.contains(hit.kind))
        }.prefix(SearchFilter.defaultLimit))
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
            NotesFilter(model: model)
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

/// 2h Filter, multiple choice: courses and note kinds in one button; "All notes" when nothing is chosen.
struct NotesFilter: View {
    @Bindable var model: SearchModel
    @Environment(Workspace.self) private var workspace
    @State private var open = false

    static func kindTitle(_ k: NoteKind) -> String {
        switch k {
        case .lecture: "Lecture notes"
        case .lab: "Labs"
        case .seminar: "Seminars"
        case .tutorial: "Tutorials"
        case .study: "Study notes"
        case .note: "Other notes"
        }
    }

    private var label: String {
        var parts: [String] = []
        if model.courses.count == 1, let id = model.courses.first, let c = workspace.courses.course(id: id) { parts.append(c.name) }
        else if model.courses.count > 1 { parts.append("\(model.courses.count) courses") }
        if model.kinds.count == 1, let k = model.kinds.first { parts.append(Self.kindTitle(k)) }
        else if model.kinds.count > 1 { parts.append("\(model.kinds.count) types") }
        return parts.isEmpty ? "All notes" : parts.joined(separator: " · ")
    }

    var body: some View {
        let active = !model.courses.isEmpty || !model.kinds.isEmpty
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Icon("filter_list", size: 16)
                Text(label)
                Icon("expand_more", size: 16)
            }
            .marginFont(MarginTextSize.base)
            .foregroundStyle(active ? MarginColor.accentText : MarginColor.ink)
            .padding(.horizontal, 10).frame(height: 32)
            .background(active ? MarginColor.accentSoft : MarginColor.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(active ? .clear : MarginColor.borderCard) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 1) {
            header("Course")
            ForEach(workspace.courses.cards) { c in
                row(c.course.name, dot: c.course.style.dot, checked: model.courses.contains(c.id)) { toggle(&model.courses, c.id) }
            }
            MarginDivider(color: Color(hex: 0xEDEEF1)).padding(.vertical, 4)
            header("Type")
            ForEach(NoteKind.allCases, id: \.self) { k in
                row(Self.kindTitle(k), dot: nil, checked: model.kinds.contains(k)) { toggle(&model.kinds, k) }
            }
            if !model.courses.isEmpty || !model.kinds.isEmpty {
                MarginDivider(color: Color(hex: 0xEDEEF1)).padding(.vertical, 4)
                row("Show all notes", dot: nil, checked: false) { model.courses = []; model.kinds = [] }
            }
        }
        .padding(5)
        .frame(width: 250)
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func header(_ title: String) -> some View {
        Text(title).marginFont(MarginTextSize.xs, .semibold).foregroundStyle(MarginColor.textTertiary)
            .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func row(_ title: String, dot: String?, checked: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon("check", size: 14, color: MarginColor.ink).frame(width: 16).opacity(checked ? 1 : 0)
                if let dot { Circle().fill(Color(hexString: dot)).frame(width: 7, height: 7) }
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
            }
            .marginFont(14).foregroundStyle(MarginColor.ink)
            .padding(.horizontal, 8).frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}
