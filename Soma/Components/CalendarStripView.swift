import SwiftUI

/// 7-day strip at the top of Home: one heart per day showing Done / To do /
/// Skipped (guide 01 of the handoff). Replaces the old flat-color-dot
/// design -- three heart states (filled / red outline / grey outline) plus
/// a legend say what a heart means without relying on color alone, a pulse
/// ring marks today, a crown marks the week's best-readiness day, and an
/// ink outline marks whichever day is currently open in DayDetailView.
struct CalendarStripView: View {
    let recommendations: [DailyRecommendation]
    let completedDates: Set<String>
    /// Dates with a real sport-goal training session -- drives the star badge.
    var goalTrainingDates: Set<String> = []
    /// The day currently open in DayDetailView, if any -- drives the ink
    /// selection outline (distinct from, and drawn outside, the state ring).
    var selectedDate: String?
    /// Tapping a day opens DayDetailView for that date -- lets the user
    /// see past workouts/recommendation, not just today's.
    var onSelectDay: (String) -> Void = { _ in }

    private let dayCount = 7
    private let circleSize: CGFloat = 34

    @State private var isPulsing = false
    @State private var isGoalPulsing = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(lastDays, id: \.dateString) { day in
                    dayColumn(day)
                }
            }

            legend
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.9).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                isGoalPulsing = true
            }
        }
    }

    // MARK: - Day column

    private func dayColumn(_ day: DayInfo) -> some View {
        let status = status(of: day.dateString)
        let isSelected = selectedDate == day.dateString
        let isBestReadiness = day.dateString == bestReadinessDate
        let hasGoalTraining = goalTrainingDates.contains(day.dateString)

        return Button {
            onSelectDay(day.dateString)
        } label: {
            VStack(spacing: 6) {
                if isBestReadiness {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SomaTokens.warn)
                        .accessibilityIdentifier("calendarCrown-\(day.dateString)")
                } else {
                    Color.clear.frame(height: 10)
                }

                Text(day.weekdayLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(SomaTokens.ink3)

                ZStack {
                    // Pulse ring -- today only, a growing/fading stroke
                    // standing in for the mockup's box-shadow pulse (not a
                    // scale on the heart itself, per guide 01 step 3).
                    if day.isToday {
                        Circle()
                            .stroke(SomaTokens.heart.opacity(isPulsing ? 0 : 0.42), lineWidth: 3)
                            .frame(width: circleSize, height: circleSize)
                            .scaleEffect(isPulsing ? 1.45 : 1.0)
                    }

                    // Only today's own goal session pulses -- a past/future
                    // goal day still gets the star, just not the glow, and
                    // the whole column is already tappable into that day's
                    // real workout via onSelectDay below.
                    if hasGoalTraining, day.isToday {
                        Circle()
                            .fill(SomaTokens.star.opacity(isGoalPulsing ? 0.22 : 0.06))
                            .frame(width: circleSize + 10, height: circleSize + 10)
                    }

                    Circle()
                        .fill(circleFill(for: status, isGoalDay: hasGoalTraining))
                        .frame(width: circleSize, height: circleSize)
                        .overlay(
                            Circle().stroke(
                                ringColor(for: status, isGoalDay: hasGoalTraining),
                                lineWidth: ringWidth(for: status)
                            )
                        )
                        // Selection outline -- 2pt ink, 2pt offset, drawn
                        // outside the state ring, never replacing it.
                        .overlay(
                            Circle()
                                .stroke(SomaTokens.ink, lineWidth: isSelected ? 2 : 0)
                                .frame(width: circleSize + 4, height: circleSize + 4)
                        )

                    if hasGoalTraining {
                        starIcon(for: status)
                            .font(.system(size: 16, weight: status == .toDo ? .semibold : .regular))
                            .accessibilityIdentifier("calendarStar-\(day.dateString)")
                    } else {
                        heartIcon(for: status)
                            .font(.system(size: 16, weight: status == .toDo ? .semibold : .regular))
                    }
                }

                Text("\(day.dayNumber)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(day.isToday ? SomaTokens.ink : SomaTokens.ink3)
            }
            .frame(maxWidth: .infinity)
            // Whole column (weekday + circle + date) is the tap target,
            // well over the 44pt minimum.
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(SomaColumnButtonStyle())
    }

    private enum DayStatus {
        case done, toDo, skipped
    }

    private func status(of dateString: String) -> DayStatus {
        if completedDates.contains(dateString) { return .done }
        let isPast = dateString < Self.todayString
        let hasRecommendation = recommendations.contains { $0.date == dateString }
        return (isPast && hasRecommendation) ? .skipped : .toDo
    }

    /// The two token families circleFill/ringColor pick between -- keeping
    /// this as one struct instead of two parallel switches means a future
    /// DayStatus case only needs updating in those two switches, not four.
    private struct GlyphTokens {
        let circleDone: Color
        let ringDone: Color
        let ringToDo: Color
    }
    private static let heartTokens = GlyphTokens(circleDone: SomaTokens.heartSoft, ringDone: SomaTokens.heartLine, ringToDo: SomaTokens.heart)
    private static let starTokens = GlyphTokens(circleDone: SomaTokens.starSoft, ringDone: SomaTokens.starLine, ringToDo: SomaTokens.star)

    private func circleFill(for status: DayStatus, isGoalDay: Bool) -> Color {
        let tokens = isGoalDay ? Self.starTokens : Self.heartTokens
        switch status {
        case .done: return tokens.circleDone
        case .toDo: return SomaTokens.surface
        case .skipped: return SomaTokens.surface3
        }
    }

    private func ringColor(for status: DayStatus, isGoalDay: Bool) -> Color {
        let tokens = isGoalDay ? Self.starTokens : Self.heartTokens
        switch status {
        case .done: return tokens.ringDone
        case .toDo: return tokens.ringToDo
        case .skipped: return SomaTokens.neutralDot
        }
    }

    private func ringWidth(for status: DayStatus) -> CGFloat {
        switch status {
        case .done: 1.5
        case .toDo: 2
        case .skipped: 1.5
        }
    }

    /// One shared glyph shape for both heart and star -- the only
    /// difference between states is fill, stroke-width and opacity, never
    /// three separate paths (guide 01 step 2), and the only difference
    /// between heart/star is which SF Symbol pair and accent color feed
    /// it. Filled red means done, and nothing else in the app may use a
    /// filled red heart.
    @ViewBuilder
    private func statusIcon(for status: DayStatus, filledSymbol: String, outlineSymbol: String, accent: Color) -> some View {
        switch status {
        case .done:
            Image(systemName: filledSymbol)
                .foregroundStyle(accent)
        case .toDo:
            Image(systemName: outlineSymbol)
                .foregroundStyle(accent)
        case .skipped:
            Image(systemName: outlineSymbol)
                .foregroundStyle(SomaTokens.ink.opacity(0.55))
        }
    }

    private func heartIcon(for status: DayStatus) -> some View {
        statusIcon(for: status, filledSymbol: "heart.fill", outlineSymbol: "heart", accent: SomaTokens.heart)
    }

    /// A goal-training day replaces the heart with a star entirely, same
    /// done/to-do/skipped fill logic as heartIcon.
    private func starIcon(for status: DayStatus) -> some View {
        statusIcon(for: status, filledSymbol: "star.fill", outlineSymbol: "star", accent: SomaTokens.star)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(.done, label: "Done")
            legendItem(.toDo, label: "To do")
            legendItem(.skipped, label: "Skipped")
        }
    }

    private func legendItem(_ status: DayStatus, label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            heartIcon(for: status).font(.system(size: 14))
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(SomaTokens.ink3)
        }
    }

    // MARK: - Best readiness (crown)

    /// The day among the 7 shown with the highest recovery-band category --
    /// crown sits on that day only. Most recent date wins ties, since it's
    /// the more actionable/relevant of the two. Never picks a day with no
    /// recommendation at all.
    private var bestReadinessDate: String? {
        Self.bestReadinessDate(among: recommendations)
    }

    /// The day among the current 7-day window with the highest recovery-
    /// band category -- shared with DayDetailView so its own crown line
    /// ("Best readiness of the week") can never disagree with the strip's
    /// crown glyph. Most recent date wins ties.
    static func bestReadinessDate(among recommendations: [DailyRecommendation]) -> String? {
        let dates = Set(lastDayStrings())
        let candidates = recommendations.filter { dates.contains($0.date) }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { lhs, rhs in
            let lhsRank = rank(lhs.category)
            let rhsRank = rank(rhs.category)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.date < rhs.date
        }?.date
    }

    private static func rank(_ category: RecommendationCategory) -> Int {
        switch category {
        case .rest: 0
        case .light: 1
        case .moderate: 2
        case .pushHard: 3
        }
    }

    private static var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    /// The exact 7 dates this strip renders (today back 6 days) -- exposed
    /// so HomeView's dashboard-entry badge can count "done" against the
    /// same window the strip itself uses. Guide 02's own rule is that if
    /// the two ever disagree, the strip wins -- sharing this window is what
    /// makes that impossible.
    static func lastDayStrings(count: Int = 7) -> [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: Date()).map(formatter.string(from:))
        }
    }

    private struct DayInfo {
        let dateString: String
        let weekdayLabel: String
        let dayNumber: Int
        let isToday: Bool
    }

    private var lastDays: [DayInfo] {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"

        return (0..<dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return DayInfo(
                dateString: dateFormatter.string(from: date),
                weekdayLabel: weekdayFormatter.string(from: date),
                dayNumber: calendar.component(.day, from: date),
                isToday: offset == 0
            )
        }
    }
}

/// Dims the column to 82% opacity while pressed -- the touch-equivalent of
/// the mockup's `:hover { opacity: .82 }` affordance the old flat dots
/// lacked (guide 01 step 6). No scale/translate, matching the button
/// system's "no bounce" rule.
private struct SomaColumnButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
