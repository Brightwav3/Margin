/// Maps a percentage (0...100) to a letter grade. Thresholds are inclusive lower bounds.
///
/// - `.us`: the `A / A− / B+ ...` scale used by the mockups (91 -> A−, 87 -> B+, 94 -> A):
///   A 93, A− 90, B+ 87, B 83, B− 80, C+ 77, C 73, C− 70, D+ 67, D 63, D− 60, else F.
/// - `.czech`: ECTS letters as used at Czech universities: A 90, B 80, C 70, D 60, E 50, else F.
public struct GradeScale: Sendable, Hashable, Codable {
    public struct Step: Sendable, Hashable, Codable {
        public var minPercent: Double
        public var letter: String
        public init(minPercent: Double, letter: String) { self.minPercent = minPercent; self.letter = letter }
    }

    public var name: String
    /// Descending by `minPercent`. Anything below the last step gets `failLetter`.
    public var steps: [Step]
    public var failLetter: String

    public init(name: String, steps: [Step], failLetter: String = "F") {
        self.name = name
        self.steps = steps.sorted { $0.minPercent > $1.minPercent }
        self.failLetter = failLetter
    }

    public static let us = GradeScale(name: "us", steps: [
        .init(minPercent: 93, letter: "A"), .init(minPercent: 90, letter: "A−"),
        .init(minPercent: 87, letter: "B+"), .init(minPercent: 83, letter: "B"),
        .init(minPercent: 80, letter: "B−"), .init(minPercent: 77, letter: "C+"),
        .init(minPercent: 73, letter: "C"), .init(minPercent: 70, letter: "C−"),
        .init(minPercent: 67, letter: "D+"), .init(minPercent: 63, letter: "D"),
        .init(minPercent: 60, letter: "D−"),
    ])

    public static let czech = GradeScale(name: "czech", steps: [
        .init(minPercent: 90, letter: "A"), .init(minPercent: 80, letter: "B"),
        .init(minPercent: 70, letter: "C"), .init(minPercent: 60, letter: "D"),
        .init(minPercent: 50, letter: "E"),
    ])

    /// Letter for `percent`; values are clamped to 0...100 and compared with a 1e-9 tolerance.
    public func letter(for percent: Double) -> String {
        let p = min(100, max(0, percent))
        return steps.first { p + 1e-9 >= $0.minPercent }?.letter ?? failLetter
    }
}
