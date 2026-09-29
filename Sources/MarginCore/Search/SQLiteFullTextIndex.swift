#if canImport(SQLite3)
import Foundation
import SQLite3

// UNVERIFIED: this file compiles only where the SQLite3 module exists (macOS). The Linux build
// image has no SQLite headers, so it has not been compiled or run by the automated checks. The
// portable `InMemoryFullTextIndex` is the reference; `FullTextIndexConformance` in the tests
// runs the same expectations against this class on macOS.

/// FTS5 index stored in `.margin/index.sqlite` (vault spec 05 §8). It is a cache: an unreadable
/// file or a different `PRAGMA user_version` drops the tables and sets `needsRebuild`, and the
/// caller then fills the index again from the markdown files.
public final class SQLiteFullTextIndex: FullTextIndex, @unchecked Sendable {
    /// Bump when the tables change; a mismatch rebuilds instead of migrating.
    public static let schemaVersion: Int32 = 1

    private let lock = NSLock()
    private var db: OpaquePointer?
    /// `true` when the index was created empty or its schema was replaced.
    public private(set) var needsRebuild = false

    /// Opens (creating when needed) the index at `path`; `nil` opens a private in-memory database.
    public init(path: String?, schemaVersion: Int32 = SQLiteFullTextIndex.schemaVersion) throws {
        if sqlite3_open(path ?? ":memory:", &db) != SQLITE_OK { throw MarginError.io("Cannot open search index") }
        do {
            try prepareSchema(version: schemaVersion)
        } catch {
            sqlite3_close(db); db = nil
            throw error
        }
    }

    deinit { sqlite3_close(db) }

    private func prepareSchema(version: Int32) throws {
        var current: Int32 = 0
        try query("PRAGMA user_version") { current = sqlite3_column_int(self.stmt, 0) }
        if current != version {
            try exec("DROP TABLE IF EXISTS fts; DROP TABLE IF EXISTS docs;")
            try exec("""
                CREATE TABLE docs (rowid INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE);
                CREATE VIRTUAL TABLE fts USING fts5(title, headings, tags, body,
                    tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3');
                PRAGMA user_version = \(version);
                """)
            needsRebuild = true
        } else {
            var n: Int32 = 0
            try query("SELECT COUNT(*) FROM docs") { n = sqlite3_column_int(self.stmt, 0) }
            needsRebuild = n == 0
        }
    }

    public var count: Int {
        lock.withLock {
            var n = 0
            try? query("SELECT COUNT(*) FROM docs") { n = Int(sqlite3_column_int(self.stmt, 0)) }
            return n
        }
    }

    public func contains(id: String) -> Bool {
        lock.withLock { (try? rowid(of: id)) != nil }
    }

    public func upsert(_ d: FullTextDocument) {
        lock.withLock {
            try? exec("BEGIN")
            do {
                try run("INSERT OR IGNORE INTO docs (id) VALUES (?1)", [d.id])
                guard let row = try rowid(of: d.id) else { throw MarginError.io("Search index row missing") }
                try run("DELETE FROM fts WHERE rowid = ?1", [row])
                try run("INSERT INTO fts (rowid, title, headings, tags, body) VALUES (?1, ?2, ?3, ?4, ?5)",
                        [row, (([d.title] + d.aliases).joined(separator: " ")), d.headings.joined(separator: " "),
                         d.tags.joined(separator: " "), d.body])
                try exec("COMMIT")
            } catch {
                try? exec("ROLLBACK")
            }
        }
    }

    public func remove(id: String) {
        lock.withLock {
            guard let row = try? rowid(of: id) else { return }
            try? run("DELETE FROM fts WHERE rowid = ?1", [row])
            try? run("DELETE FROM docs WHERE rowid = ?1", [row])
        }
    }

    public func removeAll() {
        lock.withLock { try? exec("DELETE FROM fts; DELETE FROM docs;") }
    }

    public func search(_ q: FullTextQuery, limit: Int, allowing: (@Sendable (String) -> Bool)?) -> [FullTextMatch] {
        guard !q.terms.isEmpty, limit > 0 else { return [] }
        let match = q.terms.enumerated().map { i, t -> String in
            let quoted = "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            return q.lastIsPrefix && i == q.terms.count - 1 ? quoted + "*" : quoted
        }.joined(separator: " ")
        let fetch = allowing == nil ? limit : Int.max
        return lock.withLock {
            var out: [FullTextMatch] = []
            // bm25() weights: title 5, headings 2.5, tags 2, body 1; lower (more negative) is better.
            let sql = """
                SELECT docs.id, -bm25(fts, 5.0, 2.5, 2.0, 1.0) AS score FROM fts
                JOIN docs ON docs.rowid = fts.rowid WHERE fts MATCH ?1 ORDER BY score DESC, docs.id LIMIT ?2
                """
            try? query(sql, [match, Int64(min(fetch, Int(Int32.max)))]) {
                let id = String(cString: sqlite3_column_text(self.stmt, 0))
                if allowing?(id) ?? true, out.count < limit {
                    out.append(FullTextMatch(id: id, score: sqlite3_column_double(self.stmt, 1)))
                }
            }
            return out
        }
    }

    // MARK: SQLite plumbing (callers hold `lock`, except during `init`)

    private var stmt: OpaquePointer?


    private func run(_ sql: String, _ args: [Any] = []) throws { try query(sql, args) { } }

    private func rowid(of id: String) throws -> Int64? {
        var row: Int64?
        try query("SELECT rowid FROM docs WHERE id = ?1", [id]) { row = sqlite3_column_int64(self.stmt, 0) }
        return row
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "sqlite error"
            sqlite3_free(err)
            throw MarginError.io("Search index: \(message)")
        }
    }

    private func query(_ sql: String, _ args: [Any] = [], row: () -> Void) throws {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK else {
            throw MarginError.io("Search index: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(s) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            if let text = a as? String { sqlite3_bind_text(s, idx, text, -1, transient) }
            else if let n = a as? Int64 { sqlite3_bind_int64(s, idx, n) }
        }
        stmt = s
        defer { stmt = nil }
        while true {
            let rc = sqlite3_step(s)
            if rc == SQLITE_ROW { row() } else if rc == SQLITE_DONE { break }
            else { throw MarginError.io("Search index: \(String(cString: sqlite3_errmsg(db)))") }
        }
    }
}
#endif
