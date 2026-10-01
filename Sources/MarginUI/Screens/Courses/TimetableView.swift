import MarginCore
import SwiftUI

/// 1b „Timetable first“: week header with navigation, Mon–Fri columns, 9:00–18:00 axis at
/// 56 px per hour, blocks in the course colour, today's column tinted and the red „now“ line.
struct TimetableView: View {
    @Bindable var model: CoursesOverviewModel
    var onOpen: (SessionOccurrence) -> Void = { _ in }
    /// 1k: right click on a block — reschedule or cancel (3c).
    var onReschedule: (SessionOccurrence) -> Void = { _ in }

    /// Mockup geometry (`H`, `START`, 10 hour labels).
    static let hourHeight: CGFloat = 56
    static let firstHour = 9
    static let hourCount = 10
    static let axisWidth: CGFloat = 44
    static let columnGap: CGFloat = 8
    /// Today's column background (`#F7F9FE` in the mockup; no token).
    static let todayBackground = Color(hex: 0xF7F9FE)

    static var gridHeight: CGFloat { hourHeight * CGFloat(hourCount) }

    /// Offset of a time from the top of the grid.
    static func top(of time: LocalTime) -> CGFloat {
        CGFloat(time.minutesSinceMidnight - firstHour * 60) / 60 * hourHeight
    }

    /// Block frame: 3 px below its start, `length × 56 − 6` tall.
    static func blockFrame(start: LocalTime, lengthHours: Double) -> (top: CGFloat, height: CGFloat) {
        (top(of: start) + 3, CGFloat(lengthHours) * hourHeight - 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            grid
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 40, leading: 44, bottom: 28, trailing: 28))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Week \(model.week)")
                    .marginFont(MarginTextSize.page, .bold)
                    .tracking(-0.6)
                Text(model.weekLine)
                    .marginFont(MarginTextSize.base)
                    .foregroundStyle(MarginColor.textSecondary)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                MarginButton(icon: "chevron_left") { Task { await model.showWeek(model.week - 1) } }
                    .disabled(!model.canGoBack)
                    .accessibilityLabel("Previous week")
                MarginButton("This week") { Task { await model.showThisWeek() } }
                MarginButton(icon: "chevron_right") { Task { await model.showWeek(model.week + 1) } }
                    .disabled(!model.canGoForward)
                    .accessibilityLabel("Next week")
            }
        }
    }

    private var grid: some View {
        let today = model.clock.today
        let days = model.weekDays
        return VStack(spacing: 0) {
            HStack(spacing: Self.columnGap) {
                Color.clear.frame(width: Self.axisWidth, height: 1)
                ForEach(days, id: \.self) { day in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(CoursesFormat.weekday(day.weekday)).marginFont(MarginTextSize.base, .semibold)
                        Text("\(day.day)").marginFont(MarginTextSize.sm)
                    }
                    .foregroundStyle(day == today ? MarginColor.accent : MarginColor.ink)
                    .padding(EdgeInsets(top: 0, leading: 6, bottom: 12, trailing: 6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: Self.columnGap) {
                HourAxis()
                ForEach(days, id: \.self) { day in
                    DayColumn(blocks: model.blocks.filter { $0.occurrence.date == day },
                              isToday: day == today,
                              now: day == today ? model.clock.localNow.time : nil,
                              onOpen: onOpen, onReschedule: onReschedule)
                }
            }
        }
    }
}

/// „9:00“ … „18:00“, each label centred on its hour line.
private struct HourAxis: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<TimetableView.hourCount, id: \.self) { i in
                Text("\(TimetableView.firstHour + i):00")
                    .marginFont(MarginTextSize.xs)
                    .foregroundStyle(MarginColor.textTertiary)
                    .alignmentGuide(.top) { $0.height / 2 - CGFloat(i) * TimetableView.hourHeight }
            }
        }
        .frame(width: TimetableView.axisWidth, height: TimetableView.gridHeight, alignment: .topLeading)
    }
}

private struct DayColumn: View {
    let blocks: [TimetableBlock]
    let isToday: Bool
    /// Wall-clock time for the „now“ line (today only).
    let now: LocalTime?
    let onOpen: (SessionOccurrence) -> Void
    let onReschedule: (SessionOccurrence) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: MarginRadius.sm, bottomTrailingRadius: MarginRadius.sm)
                .fill(isToday ? TimetableView.todayBackground : .clear)
            ForEach(blocks) { block in
                let frame = TimetableView.blockFrame(start: block.occurrence.session.start,
                                                     lengthHours: block.occurrence.session.lengthHours)
                SessionBlock(block: block) { onOpen(block.occurrence) }
                    .contextMenu {
                        SessionMenuItems(occurrence: block.occurrence, onOpen: onOpen, onReschedule: onReschedule)
                    }
                    .frame(height: max(0, frame.height))
                    .padding(.horizontal, 3)
                    .offset(y: frame.top)
            }
            if let now {
                let y = TimetableView.top(of: now)
                if y >= 0, y <= TimetableView.gridHeight {
                    Rectangle()
                        .fill(MarginColor.due)
                        .frame(height: 2)
                        .offset(y: y)
                        .accessibilityLabel("Now")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: TimetableView.gridHeight, alignment: .top)
        .overlay(alignment: .top) { Rectangle().fill(MarginColor.borderSubtle).frame(height: 1) }
    }
}

private struct SessionBlock: View {
    let block: TimetableBlock
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        let foreground = Color(hexString: block.style.foreground)
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.code).marginFont(MarginTextSize.sm, .semibold)
                Text(block.detail).marginFont(MarginTextSize.xs).opacity(0.85)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(hexString: block.style.background), in: RoundedRectangle(cornerRadius: MarginRadius.sm))
            .overlay {
                if hovered {
                    RoundedRectangle(cornerRadius: MarginRadius.sm).strokeBorder(foreground.opacity(0.35))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MarginRadius.sm))
            .contentShape(RoundedRectangle(cornerRadius: MarginRadius.sm))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(block.code), \(block.detail)")
    }
}


/// 1k: the menu of a class in the timetable.
struct SessionMenuItems: View {
    let occurrence: SessionOccurrence
    let onOpen: (SessionOccurrence) -> Void
    let onReschedule: (SessionOccurrence) -> Void
    @Environment(Workspace.self) private var workspace: Workspace?

    var body: some View {
        let s = occurrence.session
        let course = workspace?.courses.course(id: s.courseID)
        Section("\(s.kind) · \(CourseDetailModel.day(occurrence.date)), \(s.start.string)") {
            MenuItem("Open note", "description") { onOpen(occurrence) }
            MenuItem("Reschedule…", "event_repeat") { onReschedule(occurrence) }
            MenuItem(occurrence.isCancelled ? "Restore this session" : "Cancel this session", "event_busy") { onReschedule(occurrence) }
        }
        Divider()
        MenuItem("Add task before this", "add_task") {
            workspace?.capture.open(prefill: "\(course.map { "#\($0.code.isEmpty ? $0.name : $0.code) " } ?? "")@\(occurrence.date.adding(days: -1).iso) ")
        }
        MenuItem("Add reading", "menu_book") {
            workspace?.capture.open(prefill: "Read  for \(course?.name ?? "class") @\(occurrence.date.adding(days: -1).iso)")
        }
        Divider()
        if let course {
            MenuItem("Edit all \(CoursesFormat.weekday(s.day)) sessions…", "edit_calendar") { workspace?.dialog = .courseSettings(course) }
        }
        MenuItem("Hide \(CoursesOverviewModel.KindGroup.of(kind: s.kind).title.lowercased()) from calendar", "visibility_off") {
            workspace?.courses.toggle(CoursesOverviewModel.KindGroup.of(kind: s.kind))
        }
        Divider()
        CourseSubmenu(courseID: s.courseID)
    }
}
