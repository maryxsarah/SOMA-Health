import SwiftUI

/// 15a: full-history month-grid calendar, opened from Home's new calendar
/// icon (3a, left of the checklist ring-pill). Distinct from
/// `TrainingHistoryView` (Profile's plain 30-day log list) -- this is an
/// Oura-style grid over the same underlying signals (workout logs, daily
/// recommendations) plus steps/water, so a day's marker reads at a glance
/// instead of needing a tap.
struct HistoryCalendarView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var months: [MonthSection] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var selectedDate: String?

    @State private var workoutLogDates: Set<String> = []
    @State private var recommendationsByDate: [String: DailyRecommendation] = [:]
    @State private var dailySteps: [String: Double] = [:]
    @State private var oldestLoadedMonthStart = Date()

    /// Months fetched on first open; each "Load earlier months" tap adds
    /// this many more. Bounded, not infinite -- a manual affordance instead
    /// of scroll-position-preserving auto-prepend, which SwiftUI's
    /// `ScrollView` doesn't support cleanly.
    private static let initialMonths = 3
    private static let batchSize = 3
    private static let stepGoal = 8000
    private static let waterGoal = 8

    var body: some View {
        // 15a draws its own header row (close lens left · serif title
        // center · 40pt spacer right) and PINS it with the legend above
        // the scrolling months -- deliberately not a NavigationStack
        // toolbar: iOS 26 gives every toolbar item its own liquid-glass
        // bubble, which rendered behind the custom lens as a doubled,
        // offset circle, and the toolbar legend scrolled away with the
        // content instead of staying put ("a pinned legend, so it never
        // needs explaining").
        VStack(spacing: 12) {
            headerRow
            legendRow
                .padding(.horizontal, 18)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        ForEach(months) { month in
                            monthSection(month)
                        }
                        loadEarlierButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .padding(.top, 16)
        .somaSheetBackground()
        .sheet(isPresented: Binding(
            get: { selectedDate != nil },
            set: { if !$0 { selectedDate = nil } }
        )) {
            if let selectedDate {
                DayDetailView(date: selectedDate, recentRecommendations: Array(recommendationsByDate.values))
            }
        }
        .task { await loadInitial() }
    }

    private var headerRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SomaTokens.accent)
                    .frame(width: 40, height: 40)
                    .glassLens(cornerRadius: SomaTokens.rPill)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "historyCalendar.close", defaultValue: "Close", comment: "History calendar: button that dismisses the screen"))
            .accessibilityIdentifier("historyCalendar.closeButton")

            Spacer()

            Text(String(localized: "historyCalendar.navigationTitle", defaultValue: "History", comment: "History calendar: navigation title"))
                .font(.system(size: 22, weight: .bold, design: .serif).italic())
                .foregroundStyle(SomaTokens.ink)

            Spacer()

            // Same width as the close lens so the title truly centers.
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Legend (4 states the day markers can be in)

    /// 15a: quiet FLAT chips (white 0.55 fill + two hairline rings, no
    /// gradient, no specular, no drop shadow), centered under the title --
    /// deliberately NOT `.glassLens()`: the legend carries reference info,
    /// not affordance, and the raised lens recipe made it shout. Centered
    /// row when it fits, graceful horizontal scroll when Dynamic Type or a
    /// long localization overflows.
    private var legendRow: some View {
        ViewThatFits(in: .horizontal) {
            legendChips.frame(maxWidth: .infinity)
            ScrollView(.horizontal, showsIndicators: false) { legendChips }
        }
    }

    private var legendChips: some View {
        HStack(spacing: 5) {
            legendItem(
                label: String(localized: "historyCalendar.legend.logged", defaultValue: "Logged", comment: "History calendar legend: a day a workout was logged")
            ) {
                Image(systemName: "heart.fill").foregroundStyle(SomaTokens.accent)
            }
            legendItem(
                label: String(localized: "historyCalendar.legend.perfect", defaultValue: "Perfect", comment: "History calendar legend: a day the workout was logged and every goal (steps, water) was hit")
            ) {
                Image(systemName: "crown.fill").foregroundStyle(SomaTokens.warn)
            }
            legendItem(
                label: String(localized: "historyCalendar.legend.missed", defaultValue: "Missed", comment: "History calendar legend: a goal day that passed with nothing logged")
            ) {
                Image(systemName: "heart").foregroundStyle(SomaTokens.accent.opacity(0.4))
            }
            legendItem(
                label: String(localized: "historyCalendar.legend.rest", defaultValue: "Rest", comment: "History calendar legend: a rest day, or a day with no plan")
            ) {
                Circle()
                    .fill(Color(red: 120 / 255, green: 150 / 255, blue: 220 / 255).opacity(0.4))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func legendItem(label: String, @ViewBuilder glyph: () -> some View) -> some View {
        HStack(spacing: 5) {
            glyph().font(.system(size: 11))
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(SomaTokens.inkParagraph)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.55))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .overlay(Capsule().stroke(Color(red: 120 / 255, green: 150 / 255, blue: 220 / 255).opacity(0.16), lineWidth: 1).padding(-0.5))
        )
    }

    // MARK: - Month grid

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.veryShortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private func monthSection(_ month: MonthSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(month.title)
                    .font(.system(size: 20, weight: .bold, design: .serif).italic())
                    .foregroundStyle(SomaTokens.ink)
                Rectangle()
                    .fill(SomaTokens.hairline)
                    .frame(height: 1)
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(SomaTokens.inkPlaceholder)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(month.cells) { cell in
                    dayCellView(cell.day)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCellView(_ cell: DayCell?) -> some View {
        if let cell {
            Button {
                selectedDate = cell.dateString
            } label: {
                VStack(spacing: 4) {
                    // Fixed 30pt slot for the number OR today's gel disc --
                    // without it the 30pt disc made today's row taller and
                    // pushed its marker below every neighbor's baseline.
                    Group {
                        if cell.isToday {
                            todayDisc(dayNumber: cell.dayNumber)
                        } else {
                            Text("\(cell.dayNumber)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(cell.marker == .future ? SomaTokens.ink5 : SomaTokens.inkRowTitle)
                        }
                    }
                    .frame(height: 30)
                    // 15a keeps the marker visible under today's disc too --
                    // for today it reads as "what today is", not a verdict.
                    markerGlyph(cell.marker)
                        .frame(height: 15)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(cell.marker == .future)
            .accessibilityLabel(accessibilityLabel(for: cell))
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 52)
        }
    }

    /// 15a's "gel disc" for today -- gradient fill + inner white ring +
    /// top specular + blue drop shadow, same family as `.glassGel()` at
    /// 30pt scale, never a flat accent circle.
    private func todayDisc(dayNumber: Int) -> some View {
        Text("\(dayNumber)")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 122 / 255, green: 158 / 255, blue: 250 / 255).opacity(0.92),
                                SomaTokens.accent.opacity(0.9)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.6), location: 0),
                                    .init(color: .white.opacity(0), location: 0.45)
                                ],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    )
                    .shadow(color: SomaTokens.accent.opacity(0.3), radius: 4.5, x: 0, y: 4)
            )
    }

    @ViewBuilder
    private func markerGlyph(_ marker: DayMarker) -> some View {
        switch marker {
        case .future:
            EmptyView()
        case .rest:
            Circle()
                .fill(Color(red: 120 / 255, green: 150 / 255, blue: 220 / 255).opacity(0.3))
                .frame(width: 4, height: 4)
        case .missed:
            Image(systemName: "heart").font(.system(size: 15)).foregroundStyle(SomaTokens.accent.opacity(0.4))
        case .logged:
            Image(systemName: "heart.fill").font(.system(size: 15)).foregroundStyle(SomaTokens.accent)
        case .perfect:
            Image(systemName: "crown.fill").font(.system(size: 15)).foregroundStyle(SomaTokens.warn)
        }
    }

    private func accessibilityLabel(for cell: DayCell) -> String {
        let stateDescription: String = if cell.isToday {
            String(localized: "historyCalendar.a11y.today", defaultValue: "today", comment: "History calendar: VoiceOver suffix for today's cell")
        } else {
            switch cell.marker {
            case .future: String(localized: "historyCalendar.a11y.future", defaultValue: "upcoming", comment: "History calendar: VoiceOver state for a future day")
            case .rest: String(localized: "historyCalendar.a11y.rest", defaultValue: "rest day", comment: "History calendar: VoiceOver state for a rest day")
            case .missed: String(localized: "historyCalendar.a11y.missed", defaultValue: "missed", comment: "History calendar: VoiceOver state for a goal day nothing was logged on")
            case .logged: String(localized: "historyCalendar.a11y.logged", defaultValue: "workout logged", comment: "History calendar: VoiceOver state for a day a workout was logged")
            case .perfect: String(localized: "historyCalendar.a11y.perfect", defaultValue: "perfect day", comment: "History calendar: VoiceOver state for a day every goal was hit")
            }
        }
        return "\(month(of: cell.dateString)) \(cell.dayNumber), \(stateDescription)"
    }

    private func month(of dateString: String) -> String {
        guard let date = Self.dayFormatter.date(from: dateString) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        formatter.locale = Calendar.current.locale ?? .current
        return formatter.string(from: date)
    }

    private var loadEarlierButton: some View {
        Button {
            Task { await loadMore() }
        } label: {
            Group {
                if isLoadingMore {
                    ProgressView()
                } else {
                    Text(String(localized: "historyCalendar.loadEarlier", defaultValue: "Load earlier months", comment: "History calendar: button that fetches and shows older months"))
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(SomaTokens.accent)
            .glassLens(cornerRadius: SomaTokens.rPill)
        }
        .buttonStyle(.plain)
        .disabled(isLoadingMore)
    }

    // MARK: - Data

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static var todayString: String { dayFormatter.string(from: Date()) }

    private func loadInitial() async {
        let calendar = Calendar.current
        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let starts = (0..<Self.initialMonths).compactMap {
            calendar.date(byAdding: .month, value: -$0, to: currentMonthStart)
        }
        oldestLoadedMonthStart = starts.last ?? currentMonthStart

        await fetchLogsAndSteps(from: oldestLoadedMonthStart, to: now)
        await fetchRecommendations(from: oldestLoadedMonthStart, to: now)
        months = starts.map { buildMonth(monthStart: $0, calendar: calendar) }
        isLoading = false
    }

    private func loadMore() async {
        isLoadingMore = true
        let calendar = Calendar.current
        let newStarts = (1...Self.batchSize).compactMap {
            calendar.date(byAdding: .month, value: -$0, to: oldestLoadedMonthStart)
        }
        guard let newOldest = newStarts.last else {
            isLoadingMore = false
            return
        }
        let sliceEnd = calendar.date(byAdding: .day, value: -1, to: oldestLoadedMonthStart) ?? oldestLoadedMonthStart

        await fetchLogsAndSteps(from: newOldest, to: sliceEnd)
        oldestLoadedMonthStart = newOldest
        await fetchRecommendations(from: oldestLoadedMonthStart, to: Date())
        months.append(contentsOf: newStarts.map { buildMonth(monthStart: $0, calendar: calendar) })
        isLoadingMore = false
    }

    private func fetchLogsAndSteps(from start: Date, to end: Date) async {
        guard start <= end else { return }
        let startStr = Self.dayFormatter.string(from: start)
        let endStr = Self.dayFormatter.string(from: end)

        async let logsTask = SupabaseClient.shared.fetchWorkoutLogs(fromDate: startStr, toDate: endStr)
        async let stepsTask = HealthKitManager.shared.fetchDailySteps(from: start, to: end)

        if let logs = try? await logsTask {
            workoutLogDates.formUnion(logs.map(\.date))
        }
        dailySteps.merge(await stepsTask) { _, new in new }
    }

    private func fetchRecommendations(from start: Date, to end: Date) async {
        let days = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        guard days > 0, let recs = try? await SupabaseClient.shared.fetchRecentRecommendations(days: days) else { return }
        for rec in recs {
            recommendationsByDate[rec.date] = rec
        }
    }

    private func buildMonth(monthStart: Date, calendar: Calendar) -> MonthSection {
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart) ?? (1..<29)
        let firstWeekdayOfMonth = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7

        var days: [DayCell?] = Array(repeating: nil, count: leadingBlanks)
        for dayNumber in dayRange {
            guard let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: monthStart) else { continue }
            let dateString = Self.dayFormatter.string(from: date)
            days.append(DayCell(
                dateString: dateString,
                dayNumber: dayNumber,
                isToday: dateString == Self.todayString,
                marker: marker(for: dateString)
            ))
        }
        while days.count % 7 != 0 { days.append(nil) }

        // 15a: month header reads just "July", no year -- matches that
        // exactly for the common case (scrolling within the current year);
        // once "Load earlier months" crosses a year boundary, bare month
        // names would collide (two "August"s with no way to tell them
        // apart), so the year re-appears only then.
        let titleFormatter = DateFormatter()
        titleFormatter.dateFormat = calendar.component(.year, from: monthStart) == calendar.component(.year, from: Date()) ? "LLLL" : "LLLL yyyy"
        titleFormatter.locale = calendar.locale ?? .current
        let idFormatter = DateFormatter()
        idFormatter.dateFormat = "yyyy-MM"

        return MonthSection(
            id: idFormatter.string(from: monthStart),
            title: titleFormatter.string(from: monthStart),
            cells: days.enumerated().map { MonthDayCell(id: $0.offset, day: $0.element) }
        )
    }

    /// Same precedence as `CalendarStripView.status(of:)`: a real log always
    /// wins, even on a day the plan called for rest.
    private func marker(for dateString: String) -> DayMarker {
        guard dateString <= Self.todayString else { return .future }

        if workoutLogDates.contains(dateString) {
            let stepsOK = (dailySteps[dateString] ?? 0) >= Double(Self.stepGoal)
            let waterOK = HomeView.waterGlasses(on: dateString) >= Self.waterGoal
            return (stepsOK && waterOK) ? .perfect : .logged
        }
        if let rec = recommendationsByDate[dateString], rec.category != .rest {
            return .missed
        }
        return .rest
    }

    private enum DayMarker {
        case future, rest, missed, logged, perfect
    }

    private struct DayCell {
        let dateString: String
        let dayNumber: Int
        let isToday: Bool
        let marker: DayMarker
    }

    private struct MonthDayCell: Identifiable {
        let id: Int
        let day: DayCell?
    }

    private struct MonthSection: Identifiable {
        let id: String
        let title: String
        let cells: [MonthDayCell]
    }
}

#Preview {
    HistoryCalendarView()
}
