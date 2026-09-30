import Foundation
import Testing

/// Parent suite of every timing test. `.serialized` is inherited by the nested suites, so no two
/// performance tests run at the same time and they do not compete with each other for CPU.
/// Other (non-performance) suites still run in parallel, so each budget is additionally judged on
/// the median of several runs after a warm-up (see `perfSamples`), never on a single measurement.
@Suite(.serialized, .tags(.slow)) enum PerfSuites {}

/// Number of measured runs per budget (after one warm-up run).
let perfRuns = 5

/// Milliseconds in a `Duration`.
func perfMs(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

func perfMedian(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// One warm-up call, then `runs` measured calls; each call returns its measurement.
func perfSamples(runs: Int = perfRuns, _ body: () throws -> Double) rethrows -> [Double] {
    _ = try body()
    return try (0..<runs).map { _ in try body() }
}

func perfSamples(runs: Int = perfRuns, _ body: () async throws -> Double) async rethrows -> [Double] {
    _ = try await body()
    var out: [Double] = []
    for _ in 0..<runs { out.append(try await body()) }
    return out
}

func perfList(_ xs: [Double]) -> String {
    xs.map { String(format: "%.1f", $0) }.joined(separator: "/")
}
