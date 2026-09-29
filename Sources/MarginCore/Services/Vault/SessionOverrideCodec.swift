import Foundation

/// Reads and writes the `overrides:` list of a `_course.md` (M10-14.B).
///
/// **Spec extension (optional key, `docs/plan/05-vault-spec.md` §5).** A course may carry
///
/// ```yaml
/// overrides:
///   - {session: bio-tue-1000, date: 2026-10-06, cancelled: true, note: "Professor ill"}
///   - {session: bio-thu-1000, date: 2026-10-08, start: 2026-10-09T14:00, room: "Sci 300"}
/// ```
///
/// - `session`: the `Session.id` (`<course>-<day>-<HHmm>`) of the weekly class,
/// - `date`: the day of the occurrence being changed (a weekday matching the session),
/// - `cancelled: true`: the class does not take place (`start` and `room` are ignored),
/// - `start`: the new date and time (`YYYY-MM-DDTHH:MM`), the class may move to another day or week,
/// - `room`: the new room, `note`: free text for the change.
///
/// An entry needs `session`, `date` and one of `cancelled: true`, `start` or `room`. The key is
/// optional and unknown to older versions of the app, which ignore it; Obsidian shows it as a
/// property. Entries are kept sorted by date, then session.
enum SessionOverrideCodec {
    /// The override an entry describes, or `nil` when it is incomplete.
    static func decode(_ item: FrontmatterValue, courseID: CourseID) -> SessionOverride? {
        guard let session = item["session"]?.stringValue, !session.isEmpty, let date = item["date"]?.dateValue else { return nil }
        let cancelled = item["cancelled"]?.boolValue ?? false
        let start = item["start"].flatMap { $0.dateTimeValue ?? $0.stringValue.flatMap { LocalDateTime(iso: $0) } }
        let room = item["room"]?.stringValue
        guard cancelled || start != nil || room != nil else { return nil }
        return SessionOverride(sessionID: session, courseID: courseID, originalDate: date, cancelled: cancelled,
                               newStart: start, newRoom: room, note: item["note"]?.stringValue)
    }

    /// The entry for `override`.
    static func encode(_ o: SessionOverride) -> FrontmatterValue {
        var pairs: [FrontmatterValue.Pair] = [.init("session", .string(o.sessionID)), .init("date", .date(o.originalDate))]
        if o.cancelled { pairs.append(.init("cancelled", .bool(true))) }
        if !o.cancelled, let start = o.newStart { pairs.append(.init("start", .dateTime(start))) }
        if !o.cancelled, let room = o.newRoom { pairs.append(.init("room", .string(room))) }
        if let note = o.note { pairs.append(.init("note", .string(note))) }
        return .map(pairs)
    }

    /// The overrides of `fm`, and the entries that could not be read (kept as they are on rewrite).
    static func read(_ fm: Frontmatter, courseID: CourseID) -> (overrides: [SessionOverride], unreadable: [FrontmatterValue]) {
        var overrides: [SessionOverride] = []
        var unreadable: [FrontmatterValue] = []
        for item in fm.list(for: "overrides") ?? [] {
            if let o = decode(item, courseID: courseID) { overrides.append(o) } else { unreadable.append(item) }
        }
        return (overrides, unreadable)
    }

    /// Sets the `overrides:` key to `overrides` followed by `unreadable`; no entries removes the key.
    static func write(_ overrides: [SessionOverride], unreadable: [FrontmatterValue], to fm: inout Frontmatter) {
        let items = CourseWriting.sorted(overrides).map(encode) + unreadable
        if items.isEmpty { fm.remove("overrides") } else { fm.set("overrides", .list(items)) }
    }
}
