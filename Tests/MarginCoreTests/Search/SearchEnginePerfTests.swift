import Foundation
import Testing
@testable import MarginCore

extension PerfSuites {
    @Suite struct SearchServicePerf {
        /// M11-03: a filtered search over 1000 notes in < 50 ms; `[[` suggestions < 20 ms; excerpt < 20 ms
        /// (median of 5 after a warm-up that also builds the index).
        @Test func serviceCallsOn1000Notes() async throws {
            let index = NoteIndex(clock: FixedClock())
            await index.build(entries: SearchCorpus.entries(count: 1000))
            let engine = SearchEngine(provider: {
                await index.allNotes.map { SearchSource(record: $0, courseID: $0.courseID) }
            })
            let from = LocalDate(iso: "2026-10-05")
            let to = LocalDate(iso: "2026-10-20")
            let cases: [(String, SearchFilter)] = [
                ("mitóza", .none), ("derivace integrál", SearchFilter(course: "math")),
                ("buňka jádro", SearchFilter(kind: .lecture, from: from, to: to)),
                ("entropy", SearchFilter(tags: ["exam"])), ("the", .none), ("", SearchFilter(course: "bio", kind: .lab)),
            ]
            for (q, f) in cases {
                let samples = try await perfSamples { () async throws -> Double in
                    let t = ContinuousClock()
                    let start = t.now
                    _ = try await engine.search(query: q, filter: f)
                    return perfMs(t.now - start)
                }
                let median = perfMedian(samples)
                print("search '\(q)' \(f.course ?? "-"): \(perfList(samples)) ms")
                #expect(median < 50, "'\(q)' median \(median) ms")
            }
            let suggest = try await perfSamples { () async throws -> Double in
                let t = ContinuousClock(); let start = t.now
                _ = try await engine.suggestLinks(prefix: "deriv", course: "math", note: nil, limit: 8)
                return perfMs(t.now - start)
            }
            print("suggestLinks: \(perfList(suggest)) ms")
            #expect(perfMedian(suggest) < 20)
            let id = try #require(await index.allNotes.first?.id)
            let excerpt = try await perfSamples { () async throws -> Double in
                let t = ContinuousClock(); let start = t.now
                _ = try await engine.excerpt(note: id, heading: nil)
                return perfMs(t.now - start)
            }
            print("excerpt: \(perfList(excerpt)) ms")
            #expect(perfMedian(excerpt) < 20)
        }
    }
}
