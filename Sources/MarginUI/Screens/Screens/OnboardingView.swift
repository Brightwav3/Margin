import MarginCore
import SwiftUI

/// Screens 1a Onboarding (M11-02.U): shown while the vault has no semester. Step 1 explains the
/// vault, step 2 creates the semester, step 3 adds courses (New course dialog, syllabus).
struct OnboardingView: View {
    @Environment(Workspace.self) private var workspace
    @State private var step = 1
    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(105 * 86_400)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 22) {
                Text("Step \(step) of 3").marginFont(MarginTextSize.sm).foregroundStyle(MarginColor.textTertiary)
                switch step {
                case 1: welcome
                case 2: semester
                default: courses
                }
                HStack(spacing: 10) {
                    if step > 1 { MarginButton("Back") { step -= 1 } }
                    Spacer()
                    if step == 3 { MarginButton("Skip") { workspace.finishOnboarding() } }
                    MarginButton(step == 3 ? "Continue" : "Next", kind: .primary) { next() }
                        .disabled(step == 2 && name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(40)
            .frame(width: 560, alignment: .leading)
            .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginRadius.dialog))
            .overlay { RoundedRectangle(cornerRadius: MarginRadius.dialog).strokeBorder(MarginColor.borderCard) }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MarginColor.sidebar)
        .onAppear {
            let today = workspace.env.clock.today
            name = "\(today.month >= 8 ? "Fall" : today.month <= 5 ? "Spring" : "Summer") \(today.year)"
            if !workspace.courses.semesters.isEmpty { step = 3 }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Margin").marginFont(26, .bold).tracking(-0.5)
            Text("Lecture notes, deadlines and the timetable, organised by semester. Every note is a Markdown file you own.")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary).lineSpacing(3)
            HStack(spacing: 10) {
                Icon("folder", size: 18, color: MarginColor.textSecondary)
                Text(workspace.vaultURL?.path(percentEncoded: false) ?? "Sample data").marginFont(MarginTextSize.sm)
            }
            .padding(12)
            .background(MarginColor.sunken, in: RoundedRectangle(cornerRadius: MarginRadius.sm))
        }
    }

    private var semester: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up your semester").marginFont(26, .bold).tracking(-0.5)
            Text("Lecture notes, deadlines and the timetable are organised by semester.")
                .marginFont(MarginTextSize.base).foregroundStyle(MarginColor.textSecondary)
            VStack(alignment: .leading, spacing: 6) { FieldLabel(text: "Name"); MarginField(placeholder: "Fall 2026", text: $name) }
            HStack(spacing: 16) {
                DatePicker("Starts", selection: $start, displayedComponents: .date)
                DatePicker("Ends", selection: $end, displayedComponents: .date)
            }
            .marginFont(MarginTextSize.base)
        }
    }

    private var courses: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add your courses").marginFont(26, .bold).tracking(-0.5)
            ForEach(workspace.courses.cards) { card in
                HStack(spacing: 12) {
                    CourseTile(style: card.course.style, size: 32)
                    Text(card.course.name).marginFont(MarginTextSize.base)
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                MarginButton("Add course", icon: "add") { workspace.dialog = .newCourse }
                MarginButton("From syllabus", icon: "upload_file") {
                    if let c = workspace.courses.cards.first?.id { workspace.dialog = .syllabus(c) } else { workspace.dialog = .newCourse }
                }
            }
        }
    }

    private func next() {
        switch step {
        case 1: step = 2
        case 2:
            let clock = workspace.env.clock
            let semester = NewSemester(name: name.trimmingCharacters(in: .whitespaces),
                                       start: clock.localDateTime(from: start).date, end: clock.localDateTime(from: end).date)
            workspace.perform("Create semester") {
                _ = try await workspace.env.semesters.create(semester, actor: .user, baseVersion: nil, dryRun: false, idempotencyKey: nil)
                await workspace.courses.load()
                step = 3
            }
        default:
            workspace.finishOnboarding()
        }
    }
}

/// Screens 2c Loading: the first index of a vault.
struct LoadingView: View {
    let progress: IndexProgress

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(progress.filesDone), total: Double(max(progress.filesTotal, 1)))
                .frame(width: 280)
            HStack(spacing: 8) {
                Icon("sync", size: 16, color: MarginColor.textSecondary)
                Text("Indexing \(progress.filesDone) of \(progress.filesTotal) notes").marginFont(MarginTextSize.base)
                    .foregroundStyle(MarginColor.textSecondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MarginColor.surface)
    }
}
