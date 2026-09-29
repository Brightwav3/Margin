import Foundation

/// The analysis logic shared by `FixtureNoteAnalysis` and `VaultNoteAnalysis`: both answer from a
/// `NoteIndex`, they only differ in where the index comes from (fixture notes in memory, the open
/// vault). Sharing it is what keeps the two implementations observably identical.
struct NoteAnalysisEngine: Sendable {
    /// The index to answer from (may be rebuilt between calls).
    let index: @Sendable () async -> NoteIndex
    /// Whether a vault path is a note (not `_course.md`, not the inbox).
    let isNote: @Sendable (String) -> Bool
    /// Text counters of notes being edited, so typing recomputes only what changed.
    let trackers = StatsTrackers()

    private func record(_ id: NoteID, in index: NoteIndex) async throws -> NoteRecord {
        guard let r = await index.note(byID: id), isNote(r.path) else { throw MarginError.notFound("No note \(id)") }
        return r
    }

    func outline(id: NoteID) async throws -> [OutlineItem] {
        let index = await index()
        let r = try await record(id, in: index)
        let offset = r.bodyLineOffset
        return r.headings.map { OutlineItem(level: $0.level, text: $0.text, line: $0.line - offset) }
    }

    func backlinks(id: NoteID) async throws -> [NoteBacklink] {
        let index = await index()
        _ = try await record(id, in: index)
        var result: [NoteBacklink] = []
        for hit in await index.backlinks(to: id) where isNote(hit.sourcePath) {
            guard let source = await index.note(byPath: hit.sourcePath) else { continue }
            result.append(NoteBacklink(sourceNoteID: hit.sourceNoteID, sourceTitle: source.title,
                                       line: hit.line - source.bodyLineOffset, context: hit.snippet))
        }
        return result.sorted {
            let (a, b) = ($0.sourceTitle.lowercased(), $1.sourceTitle.lowercased())
            if a != b { return a < b }
            if $0.sourceNoteID != $1.sourceNoteID { return $0.sourceNoteID < $1.sourceNoteID }
            return $0.line < $1.line
        }
    }

    func outgoing(id: NoteID) async throws -> [OutgoingLink] {
        let index = await index()
        let r = try await record(id, in: index)
        let offset = r.bodyLineOffset
        var result: [OutgoingLink] = []
        for (link, resolution) in await index.outgoingLinks(ofPath: r.path) {
            var item = OutgoingLink(target: link.target, heading: link.heading, alias: link.alias, isEmbed: link.isEmbed,
                                    line: link.line - offset, state: .notCreated)
            switch resolution {
            case .resolved(let target):
                item.state = .resolved
                item.noteID = target
                item.title = await index.note(byID: target)?.title
            case .ambiguous(let ids):
                item.state = .ambiguous
                item.candidates = ids
            case .notCreated:
                item.state = .notCreated
            case .selfLink:
                item.state = .selfLink
            }
            result.append(item)
        }
        return result
    }

    func stats(id: NoteID, text: String?) async throws -> NoteStats {
        let index = await index()
        let r = try await record(id, in: index)
        let backlinks = await index.backlinks(to: id).filter { isNote($0.sourcePath) }.count
        if let text {
            let counts = await trackers.update(id: id, body: text)
            return NoteStats(backlinks: backlinks, properties: r.properties.count, words: counts.words,
                             openTasks: counts.openTasks, totalTasks: counts.totalTasks)
        }
        return NoteStats(backlinks: backlinks, properties: r.properties.count, words: r.wordCount,
                         openTasks: r.tasks.lazy.filter { !$0.done }.count, totalTasks: r.tasks.count)
    }

    func properties(id: NoteID) async throws -> [NoteProperty] {
        let index = await index()
        let r = try await record(id, in: index)
        guard let fm = Frontmatter.parse(r.text).frontmatter else { return [] }
        var seen = Set<String>()
        var result: [NoteProperty] = []
        for key in fm.keys where seen.insert(key).inserted {
            guard let value = fm.value(for: key) else { continue }
            let type = PropertyRegistry.builtIn.type(for: key) ?? PropertyType.infer(from: value)
            result.append(NoteProperty(key: key, type: type, value: value))
        }
        return result
    }
}

/// One `NoteStatsTracker` per note that is being edited; the least recently used are dropped.
actor StatsTrackers {
    private nonisolated let dedicatedExecutor = DedicatedExecutor(label: "margin.stats-trackers")
    nonisolated var unownedExecutor: UnownedSerialExecutor { dedicatedExecutor.asUnownedSerialExecutor() }
    private var trackers: [NoteID: NoteStatsTracker] = [:]
    private var order: [NoteID] = []
    private let capacity: Int

    init(capacity: Int = 16) { self.capacity = capacity }

    func update(id: NoteID, body: String) -> NoteTextCounts {
        var tracker = trackers[id] ?? NoteStatsTracker()
        let counts = tracker.update(body: body)
        trackers[id] = tracker
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > capacity { trackers[order.removeFirst()] = nil }
        return counts
    }
}
