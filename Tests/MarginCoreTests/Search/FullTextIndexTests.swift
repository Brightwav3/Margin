import Foundation
import Testing
@testable import MarginCore

/// Expectations every `FullTextIndex` must meet; run against each implementation.
func runFullTextIndexSuite(make: () throws -> any FullTextIndex) throws {
    // Folding: case and diacritics.
    do {
        let index = try make()
        index.upsert(FullTextDocument(id: "a", title: "Mitóza a meióza", body: "Dělení buněk"))
        index.upsert(FullTextDocument(id: "b", title: "Chemie", body: "Reakce a rovnováha"))
        #expect(index.search("MITOZA").map(\.id) == ["a"])
        #expect(index.search("mitóza").map(\.id) == ["a"])
        #expect(index.search("deleni bunek").map(\.id) == ["a"])
        #expect(index.search("rovnovaha").map(\.id) == ["b"])
        #expect(index.count == 2)
        #expect(index.contains(id: "a"))
    }
    // All words must match; the last one is a prefix while typing.
    do {
        let index = try make()
        index.upsert(FullTextDocument(id: "a", title: "Cell Biology", body: "nucleus and membrane"))
        index.upsert(FullTextDocument(id: "b", title: "Cell Cycle", body: "mitosis"))
        #expect(index.search("cell").map(\.id).sorted() == ["a", "b"])
        #expect(index.search("cell bio").map(\.id) == ["a"])
        #expect(index.search("cell bio ").map(\.id) == [])      // trailing space: "bio" must be a whole word
        #expect(index.search("cell biology").map(\.id) == ["a"])
        #expect(index.search("cell nonsense").isEmpty)
        #expect(index.search("").isEmpty)
        #expect(index.search("   ").isEmpty)
    }
    // Ranking: title beats body, more occurrences beat fewer, ties are stable.
    do {
        let index = try make()
        index.upsert(FullTextDocument(id: "body", title: "Notes", body: "the enzyme is a protein"))
        index.upsert(FullTextDocument(id: "title", title: "Enzyme", body: "a protein"))
        index.upsert(FullTextDocument(id: "many", title: "Notes two", body: "enzyme enzyme enzyme enzyme substrate"))
        let ids = index.search("enzyme").map(\.id)
        #expect(ids.first == "title")
        #expect(Set(ids) == ["title", "body", "many"])
        #expect(ids.firstIndex(of: "many")! < ids.firstIndex(of: "body")!)
    }
    // Upsert replaces, remove removes, removeAll empties.
    do {
        let index = try make()
        index.upsert(FullTextDocument(id: "a", title: "Old title", body: "alpha"))
        index.upsert(FullTextDocument(id: "a", title: "New title", body: "beta"))
        #expect(index.count == 1)
        #expect(index.search("alpha").isEmpty)
        #expect(index.search("beta").map(\.id) == ["a"])
        index.upsert(FullTextDocument(id: "b", title: "Second", body: "beta"))
        index.remove(id: "a")
        #expect(index.search("beta").map(\.id) == ["b"])
        #expect(!index.contains(id: "a"))
        index.removeAll()
        #expect(index.count == 0)
        #expect(index.search("beta").isEmpty)
    }
    // limit and allowing.
    do {
        let index = try make()
        for i in 0..<10 { index.upsert(FullTextDocument(id: "n\(i)", title: "Note \(i)", body: "shared word")) }
        #expect(index.search("shared", limit: 3).count == 3)
        #expect(index.search("shared", limit: 0).isEmpty)
        let odd = index.search(FullTextQuery("shared"), limit: 4) { Int($0.dropFirst())! % 2 == 1 }
        #expect(odd.count == 4)
        #expect(odd.allSatisfy { Int($0.id.dropFirst())! % 2 == 1 })
    }
    // Headings and tags are searched too.
    do {
        let index = try make()
        index.upsert(FullTextDocument(id: "a", title: "Lecture", headings: ["Krebs cycle"], tags: ["exam"], body: "text"))
        #expect(index.search("krebs").map(\.id) == ["a"])
        #expect(index.search("exam").map(\.id) == ["a"])
    }
}

@Suite struct FullTextIndexTests {
    @Test func inMemorySuite() throws {
        try runFullTextIndexSuite { InMemoryFullTextIndex() }
    }

    #if canImport(SQLite3)
    // UNVERIFIED on CI: runs where SQLite3 exists (macOS).
    @Test func sqliteSuite() throws {
        try runFullTextIndexSuite { try SQLiteFullTextIndex(path: nil) }
    }

    @Test func sqliteSchemaVersionMismatchRebuilds() throws {
        let path = NSTemporaryDirectory() + "margin-fts-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let a = try SQLiteFullTextIndex(path: path, schemaVersion: 1)
            #expect(a.needsRebuild)
            a.upsert(FullTextDocument(id: "x", title: "Kept", body: "words"))
        }
        do {
            let b = try SQLiteFullTextIndex(path: path, schemaVersion: 1)
            #expect(!b.needsRebuild)
            #expect(b.count == 1)
        }
        let c = try SQLiteFullTextIndex(path: path, schemaVersion: 2)
        #expect(c.needsRebuild)
        #expect(c.count == 0)
    }
    #endif

    @Test func tokenizerFoldsAndLocatesWords() {
        let text = "Přednáška č. 3: Buňka, ŠTĚPENÍ!"
        let tokens = SearchTokenizer.tokens(in: text)
        #expect(tokens.map(\.term) == ["prednaska", "c", "3", "bunka", "stepeni"])
        #expect(String(text[tokens[3].range]) == "Buňka")
        #expect(FullTextQuery("cell ").lastIsPrefix == false)
        #expect(FullTextQuery("cell").lastIsPrefix)
    }

    @Test func relevanceOnGeneratedCorpus() throws {
        let index = InMemoryFullTextIndex()
        let docs = SearchCorpus.documents(count: 200)
        for d in docs { index.upsert(d) }
        // A rare word in a title must rank that note first.
        let target = docs[17]
        let word = target.title.split(separator: " ")[0].lowercased()
        let hits = index.search("\(word) \(target.title.split(separator: " ").last!)")
        #expect(hits.first?.id == target.id)
    }
}

extension PerfSuites {
    @Suite struct FullTextIndexPerf {
        /// M10-01: a query over 1000 notes takes < 30 ms (median of 5 after a warm-up).
        @Test func queryOn1000NotesUnder30ms() throws {
            let index = InMemoryFullTextIndex()
            for d in SearchCorpus.documents(count: 1000) { index.upsert(d) }
            #expect(index.count == 1000)
            let queries = ["mitóza", "cell", "derivace integrál", "entropy reac", "the", "histo", "buňka jádro membrána", "zzzz"]
            var worst = 0.0
            for q in queries {
                let samples = perfSamples { () -> Double in
                    let clock = ContinuousClock()
                    let t = clock.measure { _ = index.search(q, limit: 50) }
                    return perfMs(t)
                }
                let median = perfMedian(samples)
                worst = max(worst, median)
                print("fts query '\(q)': \(perfList(samples)) ms")
                #expect(median < 30, "query '\(q)' median \(median) ms")
            }
            print("fts worst median: \(worst) ms")
        }
    }
}
