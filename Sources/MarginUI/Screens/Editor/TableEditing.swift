import AppKit

/// Row and column edits of a Markdown table (Margin Menus 1i), as text in, text out.
enum TableEditing {
    enum Alignment { case left, center, right }
    enum Edit: Equatable {
        case insertRow(above: Bool), insertColumn(left: Bool), deleteRow, deleteColumn, sort(ascending: Bool), align(Alignment)
    }

    /// The cells of a table line (`| a | b |` or `a | b`), trimmed; `\|` stays inside a cell.
    static func cells(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var prev: Character?
        for ch in line {
            if ch == "|", prev != "\\" { out.append(cur); cur = "" } else { cur.append(ch) }
            prev = ch
        }
        out.append(cur)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|"), !out.isEmpty { out.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|"), !out.isEmpty { out.removeLast() }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func isDelimiter(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { c in !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" } && c.contains("-") }
    }

    static func line(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }

    /// Applies `edit` to `table` (its lines without line breaks). `row` and `column` are where the
    /// pointer is (row 0 = header, 1 = the delimiter line). Returns the new lines.
    static func apply(_ edit: Edit, to table: [String], row: Int, column: Int) -> [String] {
        var rows = table.map(cells)
        let width = rows.map(\.count).max() ?? 0
        rows = rows.map { $0 + Array(repeating: "", count: max(0, width - $0.count)) }
        let delimiter = rows.firstIndex(where: isDelimiter) ?? 1
        if rows.indices.contains(delimiter) { rows[delimiter] = rows[delimiter].map { $0.isEmpty ? "---" : $0 } }
        let col = min(max(column, 0), max(width - 1, 0))
        switch edit {
        case .insertRow(let above):
            let at = row <= delimiter ? delimiter + 1 : (above ? row : row + 1)
            rows.insert(Array(repeating: "", count: width), at: min(at, rows.count))
        case .insertColumn(let left):
            let at = left ? col : col + 1
            for i in rows.indices { rows[i].insert(i == delimiter ? "---" : "", at: min(at, rows[i].count)) }
        case .deleteRow:
            guard row > delimiter, rows.indices.contains(row) else { return table }
            rows.remove(at: row)
        case .deleteColumn:
            guard width > 1 else { return table }
            for i in rows.indices where rows[i].indices.contains(col) { rows[i].remove(at: col) }
        case .sort(let ascending):
            guard delimiter + 1 < rows.count else { return table }
            var body = Array(rows[(delimiter + 1)...])
            body.sort {
                let a = $0.indices.contains(col) ? $0[col] : "", b = $1.indices.contains(col) ? $1[col] : ""
                let r = a.localizedStandardCompare(b)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
            rows.replaceSubrange((delimiter + 1)..., with: body)
        case .align(let a):
            guard rows.indices.contains(delimiter), rows[delimiter].indices.contains(col) else { return table }
            rows[delimiter][col] = switch a { case .left: ":--"; case .center: ":-:"; case .right: "--:" }
        }
        return rows.map(line)
    }

    /// Finds the table around `location` in the text view and applies `edit` as one undoable change.
    @MainActor
    static func apply(_ edit: Edit, at location: Int, handle: EditorHandle) {
        guard let tv = handle.textView else { return }
        let text = tv.string as NSString
        let here = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        func isTableLine(_ r: NSRange) -> Bool { text.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines).contains("|") }
        guard isTableLine(here) else { return }
        var start = here, end = here
        while start.location > 0 {
            let prev = text.lineRange(for: NSRange(location: start.location - 1, length: 0))
            guard isTableLine(prev) else { break }
            start = prev
        }
        while NSMaxRange(end) < text.length {
            let next = text.lineRange(for: NSRange(location: NSMaxRange(end), length: 0))
            guard isTableLine(next) else { break }
            end = next
        }
        let whole = NSRange(location: start.location, length: NSMaxRange(end) - start.location)
        let block = text.substring(with: whole)
        let trailing = block.hasSuffix("\n")
        let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
        let row = text.substring(with: NSRange(location: start.location, length: here.location - start.location))
            .components(separatedBy: "\n").count - 1
        let before = text.substring(with: NSRange(location: here.location, length: max(0, location - here.location)))
        var pipes = 0
        var prev: Character?
        for ch in before { if ch == "|", prev != "\\" { pipes += 1 }; prev = ch }
        let leading = text.substring(with: here).trimmingCharacters(in: .whitespaces).hasPrefix("|")
        let column = max(0, pipes - (leading ? 1 : 0))
        let out = apply(edit, to: lines, row: row, column: column)
        tv.replace(whole, with: out.joined(separator: "\n") + (trailing ? "\n" : ""))
    }
}
