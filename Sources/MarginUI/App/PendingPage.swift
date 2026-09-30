import MarginCore
import SwiftUI

/// Stand-in for pages that later milestones build, so an opened tab shows what it is.
struct PendingPage: View {
    let course: Course?
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 14) {
            if let course { CourseTile(style: course.style, size: 52) }
            Text(title).marginFont(MarginTextSize.lg, .semibold)
            Text(detail).marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
