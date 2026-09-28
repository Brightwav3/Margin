/// Parses one line of quick capture into a `CaptureDraft` (M8-01).
///
/// Recognised, all relative to the injected `Clock`:
/// - **Course**: name, code, code prefix, id, nicknames and professor surname of the injected
///   course list (`CourseAliasIndex`), or a `#hashtag` that names a course. A hashtag wins over a
///   plain word, then higher-priority aliases (name/code before nickname before surname), then the
///   earliest mention.
/// - **Due date**: `@token` (`DueToken` grammar, resolved by `DueResolver`), a bare ISO date, or
///   natural language: today, tonight, tomorrow, day after tomorrow, weekday names (`friday`, and
///   `fri` only after a preposition), `next week`, `next|this <weekday>`, `in 3 days|weeks`,
///   `oct 5`, `5th of october [2027]`. Optional preposition (`by`, `on`, `until`, `due`, `for`) and
///   time (`5pm`, `at 17:00`, `noon`) belong to the highlighted span. Weekdays resolve like
///   `@Tue` (strictly after today). A month/day already past this year means next year. When
///   several dates appear, an explicit `@` token wins, then a bare ISO date, then the last
///   natural-language date.
/// - **Tags**: `#word` (lowercased, unique, not pure digits). A hashtag that became the course is
///   not a tag.
/// - **Kind**: `note:`/`idea:`/`thought:`/`quote:` prefix -> note, `task:`/`todo:` -> task,
///   `link:` -> link; else an image file or URL to an image -> image, URL -> link; attach hint
///   without a date -> note; otherwise task.
/// - **Attach**: `to|into|for lecture [notes] [N]` sets `lectureHint`; with `notes` given the
///   note is resolved to `draft.attachTo` (numbered lecture, else the latest one up to today).
public struct QuickCaptureParser: Sendable {
    public let clock: any Clock
    private let courses: [Course]
    private let notes: [NoteSummary]
    private let aliases: CourseAliasIndex

    /// - Parameters:
    ///   - courses: the courses of the current semester.
    ///   - notes: lecture notes used to resolve `attachTo`; empty leaves `attachTo` nil.
    ///   - extraAliases: explicit alias table per course id, on top of derived and built-in ones.
    ///   - useDefaultNicknames: turns off the built-in nickname table (`orgo`, `linalg`, ...).
    public init(courses: [Course], clock: any Clock, notes: [NoteSummary] = [],
                extraAliases: [CourseID: [String]] = [:], useDefaultNicknames: Bool = true) {
        self.clock = clock; self.courses = courses; self.notes = notes
        self.aliases = CourseAliasIndex(courses: courses, extraAliases: extraAliases,
                                        useDefaultNicknames: useDefaultNicknames)
    }

    // MARK: - Internal model

    private struct Tok {
        var text: String
        var start: Int
        var end: Int
    }

    private enum DateSource {
        case token(DueToken)
        case date(LocalDate)
    }

    private struct DateCandidate {
        var source: DateSource
        var range: Range<Int>
        var priority: Int
        var time: LocalTime?
        /// Tokens swallowed by a natural-language date (so course matching skips them).
        var tokenRange: Range<Int>?
    }

    private struct Hashtag {
        var name: String
        var range: Range<Int>
    }

    private static let prefixKinds: [String: InboxKind] = [
        "note": .note, "notes": .note, "idea": .note, "thought": .note, "quote": .note,
        "task": .task, "todo": .task, "link": .link,
    ]
    private static let prepositions: Set<String> = ["by", "on", "until", "till", "due", "for"]
    private static let imageExtensions = [".png", ".jpg", ".jpeg", ".heic", ".gif", ".webp"]
    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]
    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]

    // MARK: - Parse

    public func parse(_ input: String) -> ParsedCapture {
        let chars = Array(input)
        let n = chars.count
        var used = [Bool](repeating: false, count: n)
        var removed = [Bool](repeating: false, count: n)
        var spans: [CaptureSpan] = []

        // 1. Kind prefix ("note:").
        var explicitKind: InboxKind?
        var start = 0
        while start < n, chars[start].isWhitespace { start += 1 }
        var e = start
        while e < n, chars[e].isLetter { e += 1 }
        if e > start, e < n, chars[e] == ":",
           let k = Self.prefixKinds[String(chars[start..<e]).lowercased()] {
            explicitKind = k
            for i in start...e { used[i] = true; removed[i] = true }
            spans.append(CaptureSpan(kind: .kindPrefix, range: start..<(e + 1)))
        }
        let prefixOnlyRemoved = removed

        // 2. URLs and image files (whitespace-separated words).
        var hasURL = false, hasImage = false
        var w = 0
        while w < n {
            if used[w] || chars[w].isWhitespace { w += 1; continue }
            var we = w
            while we < n, !chars[we].isWhitespace { we += 1 }
            let lower = String(chars[w..<we]).lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") {
                var ue = we
                while ue > w, ".,;:!?)]>\"'".contains(chars[ue - 1]) { ue -= 1 }
                for i in w..<ue { used[i] = true }
                spans.append(CaptureSpan(kind: .url, range: w..<ue))
                hasURL = true
                let path = String(chars[w..<ue]).lowercased()
                if Self.imageExtensions.contains(where: { path.hasSuffix($0) }) { hasImage = true }
            } else {
                let bare = lower.trimmingCharacters(in: ".,;:!?)]>\"'")
                if bare.count > 4, Self.imageExtensions.contains(where: { bare.hasSuffix($0) }) { hasImage = true }
            }
            w = we
        }

        // 3. `@due`, bare ISO dates and `#tags`.
        var candidates: [DateCandidate] = []
        var hashtags: [Hashtag] = []
        var p = 0
        while p < n {
            if used[p] { p += 1; continue }
            let c = chars[p]
            if c == "@", p == 0 || chars[p - 1].isWhitespace {
                var q = p + 1
                while q < n, !used[q], Self.isAsciiWord(chars[q]) || chars[q] == "-" { q += 1 }
                while q > p + 1, chars[q - 1] == "-" { q -= 1 }
                if q > p + 1, let tok = DueToken(word: String(chars[(p + 1)..<q])) {
                    for i in p..<q { used[i] = true; removed[i] = true }
                    candidates.append(DateCandidate(source: .token(tok), range: p..<q, priority: 2))
                    p = q; continue
                }
            } else if c == "#", p == 0 || chars[p - 1].isWhitespace || "([{".contains(chars[p - 1]) {
                var q = p + 1
                while q < n, !used[q], chars[q].isLetter || chars[q].isNumber || "-_/".contains(chars[q]) { q += 1 }
                while q > p + 1, "-_/".contains(chars[q - 1]) { q -= 1 }
                if q > p + 1, chars[(p + 1)..<q].contains(where: \.isLetter) {
                    for i in p..<q { used[i] = true; removed[i] = true }
                    hashtags.append(Hashtag(name: String(chars[(p + 1)..<q]).lowercased(), range: p..<q))
                    p = q; continue
                }
            } else if Self.isDigit(c), p == 0 || !(chars[p - 1].isLetter || chars[p - 1].isNumber || chars[p - 1] == "-"),
                      p + 10 <= n, Self.looksLikeISO(chars, p),
                      p + 10 == n || !(chars[p + 10].isLetter || chars[p + 10].isNumber),
                      let d = LocalDate(iso: String(chars[p..<(p + 10)])),
                      !(p..<(p + 10)).contains(where: { used[$0] }) {
                for i in p..<(p + 10) { used[i] = true }
                candidates.append(DateCandidate(source: .date(d), range: p..<(p + 10), priority: 1))
                p += 10; continue
            }
            p += 1
        }

        // 4. Tokenise what is left.
        var toks: [Tok] = []
        var t = 0
        while t < n {
            if used[t] || !(chars[t].isLetter || chars[t].isNumber) { t += 1; continue }
            var u = t
            while u < n, !used[u] {
                let ch = chars[u]
                if ch.isLetter || ch.isNumber { u += 1 }
                else if ch == ":", u > t, Self.isDigit(chars[u - 1]), u + 1 < n, Self.isDigit(chars[u + 1]), !used[u + 1] { u += 1 }
                else { break }
            }
            toks.append(Tok(text: String(chars[t..<u]).lowercased(), start: t, end: u))
            t = u
        }
        var consumed = [Bool](repeating: false, count: toks.count)
        let plain = QuickCaptureParser.dueResolver(clock: clock, context: .empty)

        // 5. Natural-language dates.
        var ti = 0
        while ti < toks.count {
            var hit: (first: Int, last: Int, date: LocalDate, time: LocalTime?)?
            if let (len, date) = matchDate(toks, ti, hasPrep: false, plain) {
                let (extra, time) = withTime(toks, ti + len)
                hit = (ti, ti + len + extra - 1, date, time)
            } else if Self.prepositions.contains(toks[ti].text), ti + 1 < toks.count,
                      let (len, date) = matchDate(toks, ti + 1, hasPrep: true, plain) {
                let (extra, time) = withTime(toks, ti + 1 + len)
                hit = (ti, ti + len + extra, date, time)
            }
            // A phrase must be contiguous: reject one that straddles a URL, `#tag` or `@token`.
            if let h = hit, !(toks[h.first].start..<toks[h.last].end).contains(where: { used[$0] }) {
                candidates.append(DateCandidate(source: .date(h.date), range: toks[h.first].start..<toks[h.last].end,
                                                priority: 0, time: h.time, tokenRange: h.first..<(h.last + 1)))
                ti = h.last + 1
            } else {
                ti += 1
            }
        }

        // 6. Attachment hint ("to lecture 8").
        var hint: CaptureLectureHint?
        var lectureSpanTokens: Range<Int>?
        var ai = 0
        while ai + 1 < toks.count, hint == nil {
            let word = toks[ai + 1].text
            if ["to", "into", "for"].contains(toks[ai].text), !consumed[ai], !consumed[ai + 1],
               ["lecture", "lectures", "lec"].contains(word) {
                var k = ai + 2
                if k < toks.count, ["notes", "note"].contains(toks[k].text) { k += 1 }
                var number: Int?
                if k < toks.count, toks[k].text.count <= 3, let v = Int(toks[k].text) { number = v; k += 1 }
                if k < toks.count, ["notes", "note"].contains(toks[k].text) { k += 1 }
                hint = CaptureLectureHint(number: number)
                lectureSpanTokens = ai..<k
            }
            ai += 1
        }
        // A date phrase swallowed by the attachment ("for lecture 8" never is) stays valid;
        // tokens of the attachment must not be matched as courses or dates.
        if let r = lectureSpanTokens {
            for i in r { consumed[i] = true }
            candidates.removeAll { c in
                guard let tr = c.tokenRange else { return false }
                return tr.overlaps(r)
            }
        }

        // 7. Choose the date.
        let chosen = candidates.max { ($0.priority, $0.range.lowerBound) < ($1.priority, $1.range.lowerBound) }
        var chosenRange = chosen?.range
        var dueTime = chosen?.time
        if let c = chosen {
            if c.tokenRange == nil {
                // Explicit `@`/ISO: pick up a trailing time and, for ISO, a leading preposition.
                if let after = toks.firstIndex(where: { $0.start >= c.range.upperBound }),
                   toks[after].start - c.range.upperBound <= 2,
                   let (len, time) = matchTime(toks, after) {
                    dueTime = time
                    for i in after..<(after + len) { consumed[i] = true }
                    if c.priority == 1 { chosenRange = c.range.lowerBound..<toks[after + len - 1].end }
                }
                if c.priority == 1, let before = toks.lastIndex(where: { $0.end <= c.range.lowerBound }),
                   Self.prepositions.contains(toks[before].text),
                   chars[toks[before].end..<c.range.lowerBound].allSatisfy(\.isWhitespace) {
                    chosenRange = toks[before].start..<(chosenRange?.upperBound ?? c.range.upperBound)
                    consumed[before] = true
                }
            } else if let tr = c.tokenRange {
                for i in tr { consumed[i] = true }
            }
        }

        // 8. Course.
        let words = toks.map(\.text)
        var best: (score: Int, pos: Int, course: CourseID, range: Range<Int>, hashtag: Int?)?
        func consider(_ score: Int, _ pos: Int, _ course: CourseID, _ range: Range<Int>, _ hashtag: Int?) {
            if best == nil || score > best!.score || (score == best!.score && pos < best!.pos) {
                best = (score, pos, course, range, hashtag)
            }
        }
        var mi = 0
        while mi < toks.count {
            if !consumed[mi], let m = aliases.match(words: words, at: mi, isFree: { !consumed[$0] }) {
                consider(m.entry.priority, toks[mi].start, m.entry.course, toks[mi].start..<toks[mi + m.length - 1].end, nil)
                mi += m.length
            } else {
                mi += 1
            }
        }
        for (h, tag) in hashtags.enumerated() {
            let key = CourseAliasIndex.tokens(tag.name).joined(separator: " ")
            if let entry = aliases.table[key] { consider(entry.priority + 10, tag.range.lowerBound, entry.course, tag.range, h) }
        }

        // 9. Resolve the due date (course events narrow to the detected course).
        var due: LocalDate?
        if let c = chosen {
            switch c.source {
            case .date(let d): due = d
            case .token(let tok):
                let scoped = courses.filter { best == nil || $0.id == best!.course }
                let ctx = CourseEventContext(exams: scoped.flatMap(\.exams), sessions: scoped.flatMap(\.sessions))
                due = Self.dueResolver(clock: clock, context: ctx).resolve(tok)
            }
        }

        // 10. Assemble.
        var tags: [String] = []
        for (h, tag) in hashtags.enumerated() where h != best?.hashtag {
            if !tags.contains(tag.name) { tags.append(tag.name) }
            spans.append(CaptureSpan(kind: .tag, range: tag.range))
        }
        if let b = best { spans.append(CaptureSpan(kind: .course, range: b.range)) }
        if due != nil, let r = chosenRange { spans.append(CaptureSpan(kind: .date, range: r)) }
        else { dueTime = nil }
        if let r = lectureSpanTokens, r.lowerBound < r.upperBound {
            spans.append(CaptureSpan(kind: .attachment, range: toks[r.lowerBound].start..<toks[r.upperBound - 1].end))
        }
        spans.sort { $0.range.lowerBound < $1.range.lowerBound }

        var kind: InboxKind = .task
        if let k = explicitKind { kind = k }
        else if hasImage { kind = .image }
        else if hasURL { kind = .link }
        else if hint != nil, due == nil { kind = .note }

        var text = Self.collapse(chars, removed)
        if text.isEmpty { text = Self.collapse(chars, prefixOnlyRemoved) }

        let attach = hint.flatMap { attachTarget($0, course: best?.course) }
        let draft = CaptureDraft(text: text, course: best?.course, due: due, tags: tags, kind: kind, attachTo: attach)
        return ParsedCapture(draft: draft, spans: spans, dueTime: dueTime, lectureHint: hint)
    }

    // MARK: - Dates

    private static func dueResolver(clock: any Clock, context: CourseEventContext) -> DueResolver {
        DueResolver(clock: clock, context: context)
    }

    /// Natural-language date starting at `toks[i]`: number of tokens and the resolved day.
    private func matchDate(_ toks: [Tok], _ i: Int, hasPrep: Bool, _ resolver: DueResolver) -> (Int, LocalDate)? {
        let t = toks[i].text
        let count = toks.count
        let next = i + 1 < count ? toks[i + 1].text : nil
        switch t {
        case "today", "tonight": return resolver.resolve(.today).map { (1, $0) }
        case "tomorrow", "tmrw", "tmr": return resolver.resolve(.tomorrow).map { (1, $0) }
        case "day":
            if next == "after", i + 2 < count, toks[i + 2].text == "tomorrow" {
                return (3, clock.today.adding(days: 2))
            }
        case "next", "this":
            if let next {
                if t == "next", next == "week" { return resolver.resolve(.nextWeek).map { (2, $0) } }
                if let wd = Self.weekday(next, allowAbbrev: true) { return resolver.resolve(.weekday(wd)).map { (2, $0) } }
            }
        case "in":
            if i + 2 < count, let n = Int(toks[i + 1].text) ?? Self.numberWords[toks[i + 1].text], (1...365).contains(n) {
                let unit = toks[i + 2].text
                if ["day", "days"].contains(unit) { return (3, clock.today.adding(days: n)) }
                if ["week", "weeks", "wk", "wks"].contains(unit) { return (3, clock.today.adding(days: 7 * n)) }
            }
        default: break
        }
        if let wd = Self.weekday(t, allowAbbrev: hasPrep) {
            return resolver.resolve(.weekday(wd)).map { (1, $0) }
        }
        return matchMonthDay(toks, i, hasPrep: hasPrep)
    }

    private static func weekday(_ s: String, allowAbbrev: Bool) -> Weekday? {
        if let wd = Weekday.allCases.first(where: { $0.fullName == s }) { return wd }
        guard allowAbbrev else { return nil }
        switch s {
        case "tues": return .tuesday
        case "thur", "thurs": return .thursday
        case "weds": return .wednesday
        default: return Weekday(token: s)
        }
    }

    private static func parseDay(_ s: String) -> Int? {
        var digits = Substring(s)
        for suffix in ["st", "nd", "rd", "th"] where digits.hasSuffix(suffix) && digits.count > suffix.count {
            digits = digits.dropLast(suffix.count)
            break
        }
        guard digits.count <= 2, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let d = Int(digits), (1...31).contains(d) else { return nil }
        return d
    }

    /// `oct 5 [2027]`, `5 oct`, `5th of october`.
    private func matchMonthDay(_ toks: [Tok], _ i: Int, hasPrep: Bool) -> (Int, LocalDate)? {
        func month(_ s: String) -> Int? {
            guard let m = Self.months[s] else { return nil }
            return s == "may" && !hasPrep ? nil : m
        }
        var m: Int?, d: Int?, len = 0
        if let mm = month(toks[i].text), i + 1 < toks.count, let dd = Self.parseDay(toks[i + 1].text) {
            m = mm; d = dd; len = 2
        } else if let dd = Self.parseDay(toks[i].text), i + 1 < toks.count {
            if let mm = month(toks[i + 1].text) { m = mm; d = dd; len = 2 }
            else if toks[i + 1].text == "of", i + 2 < toks.count, let mm = month(toks[i + 2].text) { m = mm; d = dd; len = 3 }
        }
        guard let m, let d else { return nil }
        var year = clock.today.year
        var explicitYear = false
        if i + len < toks.count, toks[i + len].text.count == 4, let y = Int(toks[i + len].text), (2000...2100).contains(y) {
            year = y; explicitYear = true; len += 1
        }
        guard var date = LocalDate(year: year, month: m, day: d) else { return nil }
        if !explicitYear, date < clock.today, let nextYear = LocalDate(year: year + 1, month: m, day: d) { date = nextYear }
        return (len, date)
    }

    /// Optional time right after a date: (extra tokens consumed, time).
    private func withTime(_ toks: [Tok], _ i: Int) -> (Int, LocalTime?) {
        guard i < toks.count, let (len, time) = matchTime(toks, i) else { return (0, nil) }
        return (len, time)
    }

    /// `5pm`, `5:30pm`, `5 pm`, `17:00`, `noon`, each optionally after `at`.
    private func matchTime(_ toks: [Tok], _ i: Int) -> (Int, LocalTime)? {
        guard i < toks.count else { return nil }
        var k = i
        if toks[k].text == "at" { k += 1 }
        guard k < toks.count else { return nil }
        let t = toks[k].text
        if t == "noon" { return LocalTime(hour: 12, minute: 0).map { (k - i + 1, $0) } }
        let chars = Array(t)
        var p = 0
        while p < chars.count, Self.isDigit(chars[p]) { p += 1 }
        guard (1...2).contains(p), let hour = Int(String(chars[0..<p])) else { return nil }
        var minute = 0
        var hasColon = false
        if p < chars.count, chars[p] == ":" {
            guard chars.count >= p + 3, Self.isDigit(chars[p + 1]), Self.isDigit(chars[p + 2]),
                  let mn = Int(String(chars[(p + 1)...(p + 2)])) else { return nil }
            minute = mn; hasColon = true; p += 3
        }
        var suffix = String(chars[p...])
        var used = k - i + 1
        if suffix.isEmpty, k + 1 < toks.count, ["am", "pm"].contains(toks[k + 1].text) {
            suffix = toks[k + 1].text; used += 1
        }
        switch suffix {
        case "":
            guard hasColon else { return nil }
            return LocalTime(hour: hour, minute: minute).map { (used, $0) }
        case "am", "pm":
            guard (1...12).contains(hour) else { return nil }
            let h = suffix == "pm" ? hour % 12 + 12 : hour % 12
            return LocalTime(hour: h, minute: minute).map { (used, $0) }
        default:
            return nil
        }
    }

    // MARK: - Attachment

    /// Lecture note to append to: the numbered lecture of `course`, else its latest lecture up to today.
    private func attachTarget(_ hint: CaptureLectureHint, course: CourseID?) -> NoteID? {
        guard let course else { return nil }
        let lectures = notes.filter { $0.courseID == course && $0.kind == .lecture }
        if let n = hint.number {
            let prefix = "lecture \(n)"
            return lectures.first {
                let title = $0.title.lowercased()
                guard title.hasPrefix(prefix) else { return false }
                let rest = title.dropFirst(prefix.count)
                return rest.first.map { !$0.isNumber } ?? true
            }?.id
        }
        let today = clock.today
        return lectures.filter { ($0.date ?? .literal(9999, 1, 1)) <= today && $0.date != nil }
            .max { ($0.date ?? today) < ($1.date ?? today) }?.id
    }

    // MARK: - Helpers

    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    private static func isAsciiWord(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }

    private static func looksLikeISO(_ c: [Character], _ p: Int) -> Bool {
        for k in 0..<10 {
            let ch = c[p + k]
            if k == 4 || k == 7 { if ch != "-" { return false } } else if !isDigit(ch) { return false }
        }
        return true
    }

    /// The characters not marked removed, with whitespace runs collapsed and trimmed.
    private static func collapse(_ chars: [Character], _ removed: [Bool]) -> String {
        var out = ""
        var pendingSpace = false
        for (i, c) in chars.enumerated() where !removed[i] {
            if c.isWhitespace { pendingSpace = !out.isEmpty; continue }
            if pendingSpace { out.append(" "); pendingSpace = false }
            out.append(c)
        }
        return out
    }
}

extension String {
    fileprivate func trimmingCharacters(in set: String) -> String {
        var s = Substring(self)
        while let f = s.first, set.contains(f) { s = s.dropFirst() }
        while let l = s.last, set.contains(l) { s = s.dropLast() }
        return String(s)
    }
}
