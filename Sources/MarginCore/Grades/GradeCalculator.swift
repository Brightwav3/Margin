import Foundation

/// Pure grade maths (no file I/O; `GradeStore` comes later).
///
/// Rules:
/// - An item is graded when `score` is set and `max > 0`; others are pending and ignored.
/// - Group percentage = sum(score) / sum(max) over the graded items of the group (points based,
///   so a bigger item counts more inside its group).
/// - Course percentage = sum(weight * groupPercent) / sum(weight) over the groups that have at
///   least one graded item ("renormalised over graded groups"): missing groups neither help nor
///   hurt, so the number is "your grade so far".
/// - Groups are matched to `_course.md` grading parts by label (case-insensitive, trimmed).
///   Items whose group is `nil` or unknown are not counted and are listed in `ignoredItemIDs`.
/// - Without grading parts, all graded items form one group (points based).
/// - No dropped lowest scores, no extra credit.
/// - Semester average = mean of course percentages weighted by credits; courses without a
///   percentage are skipped, courses without credits count as 1 credit.
public enum GradeCalculator {
    public struct GroupResult: Sendable, Hashable, Codable {
        public var label: String
        public var weightPercent: Int
        /// `nil` when nothing in the group is graded yet.
        public var percent: Double?
        public var gradedCount: Int
        public var totalCount: Int
    }

    public struct CourseResult: Sendable, Hashable, Codable {
        public var courseID: CourseID
        /// `nil` when nothing is graded.
        public var percent: Double?
        public var letter: String?
        /// Sum of the weights of the groups that entered the average (0...100 when weights sum to 100).
        public var gradedWeightPercent: Int
        public var groups: [GroupResult]
        public var ignoredItemIDs: [String]

        /// Standing in the shape the API uses (percent rounded to an integer).
        public var summary: GradeSummary? {
            guard let percent, let letter else { return nil }
            return GradeSummary(courseID: courseID, letter: letter, percent: Int(percent.rounded()))
        }
    }

    public struct SemesterResult: Sendable, Hashable, Codable {
        public var percent: Double?
        public var letter: String?
        public var courses: [CourseResult]
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isGraded(_ g: Grade) -> Bool {
        guard let score = g.score, let max = g.max else { return false }
        return max > 0 && score.isFinite
    }

    private static func points(_ items: [Grade]) -> Double? {
        let graded = items.filter(isGraded)
        let total = graded.reduce(0.0) { $0 + ($1.max ?? 0) }
        guard total > 0 else { return nil }
        return graded.reduce(0.0) { $0 + ($1.score ?? 0) } / total * 100
    }

    public static func course(id: CourseID, grading: [GradingPart], grades: [Grade],
                              scale: GradeScale = .us) -> CourseResult {
        let items = grades.filter { $0.courseID == id }
        var groups: [GroupResult] = []
        var ignored: [String] = []
        var weighted = 0.0, weightSum = 0

        if grading.isEmpty {
            let p = points(items)
            let n = items.filter(isGraded).count
            groups.append(GroupResult(label: "", weightPercent: 100, percent: p, gradedCount: n, totalCount: items.count))
            if let p { weighted = p * 100; weightSum = 100 }
        } else {
            let known = Set(grading.map { normalized($0.label) })
            ignored = items.filter { g in g.group.map { !known.contains(normalized($0)) } ?? true }.map(\.id)
            for part in grading {
                let mine = items.filter { $0.group.map(normalized) == normalized(part.label) }
                let p = points(mine)
                groups.append(GroupResult(label: part.label, weightPercent: part.weightPercent, percent: p,
                                          gradedCount: mine.filter(isGraded).count, totalCount: mine.count))
                if let p, part.weightPercent > 0 {
                    weighted += p * Double(part.weightPercent); weightSum += part.weightPercent
                }
            }
        }
        let percent: Double? = weightSum > 0 ? weighted / Double(weightSum) : nil
        return CourseResult(courseID: id, percent: percent, letter: percent.map(scale.letter(for:)),
                            gradedWeightPercent: weightSum, groups: groups, ignoredItemIDs: ignored)
    }

    public static func course(_ course: Course, grades: [Grade], scale: GradeScale = .us) -> CourseResult {
        self.course(id: course.id, grading: course.grading, grades: grades, scale: scale)
    }

    public static func semester(courses: [Course], grades: [Grade], scale: GradeScale = .us) -> SemesterResult {
        let results = courses.map { course($0, grades: grades, scale: scale) }
        var sum = 0.0, credits = 0.0
        for (c, r) in zip(courses, results) {
            guard let p = r.percent else { continue }
            let w = Double(max(0, c.credits ?? 1))
            sum += p * w; credits += w
        }
        let percent: Double? = credits > 0 ? sum / credits : nil
        return SemesterResult(percent: percent, letter: percent.map(scale.letter(for:)), courses: results)
    }
}
