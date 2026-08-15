import SwiftUI

/// 7-day strip at the top of Home: one heart per day showing Done / To do /
/// Skipped. Per the Soma Glass handoff (screen 3a): "hearts (blue filled /
/// green custom / glowing today / outline planned)" -- blue filled = a
/// completed session, green = a goal-training ("custom") day, a glowing
/// blue ring marks today, outline marks a planned/future day. A crown
/// marks the week's best-readiness day, and an ink outline marks whichever
/// day is currently open in DayDetailView.
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

    /// Drives today's glow -- an in-out toggle (not a one-way pulse), same
    /// curve as `WeekHeartsStrip`'s `glow` state.
    @State private var isPulsing = false

    var body: some View {
        // No legend row -- per 3a, state reads from the hearts themselves
        // (5 distinct disc/glyph treatments), a caption underneath is noise.
        HStack(spacing: 10) {
            ForEach(lastDays, id: \.dateString) { day in
                dayColumn(day)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    // MARK: - Day column

    private func dayColumn(_ day: DayInfo) -> some View {
        let status = status(of: day.dateString)
        let isSelected = selectedDate == day.dateString
        let hasGoalTraining = goalTrainingDates.contains(day.dateString)

        return Button {
            onSelectDay(day.dateString)
        } label: {
            VStack(spacing: 6) {
                Text(day.weekdayLabel)
                    .font(.system(size: 11, weight: day.isToday ? .bold : .regular))
                    .foregroundStyle(day.isToday ? SomaTokens.accent : SomaTokens.ink3)

                disc(status: status, isGoalDay: hasGoalTraining, isToday: day.isToday, dateString: day.dateString)
                    // Selection outline -- 2pt ink, drawn outside the
                    // state ring, never replacing it.
                    .overlay(
                        Circle()
                            .stroke(SomaTokens.ink, lineWidth: isSelected ? 2 : 0)
                            .frame(width: circleSize + 4, height: circleSize + 4)
                    )

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

    /// The done-state fill is the mockup's own exact swatch (#3D66EE) --
    /// close to but distinct from `SomaTokens.accent`, kept as its own
    /// constant rather than repointing the shared accent token for one glyph.
    private static let heartDoneFill = Color(red: 0x3D / 255, green: 0x66 / 255, blue: 0xEE / 255)

    /// The 5 exact disc recipes from the 3a handoff (`WeekHeartsStrip` in
    /// `GlassDashboard3A.swift`) -- today always wins over status (a
    /// completed "today" still reads as the glowing state, matching the
    /// mockup's own example), everything else is status × goal-day.
    @ViewBuilder
    private func disc(status: DayStatus, isGoalDay: Bool, isToday: Bool, dateString: String) -> some View {
        let a11yId = isGoalDay ? "calendarStar-\(dateString)" : "calendarHeart-\(dateString)"

        if isToday {
            ZStack {
                Circle().fill(Color.white.opacity(0.55))
                Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                Circle().stroke(SomaTokens.accent.opacity(isPulsing ? 0.5 : 0.3), lineWidth: isPulsing ? 1.5 : 1)
                    .shadow(color: SomaTokens.accent.opacity(isPulsing ? 0.45 : 0), radius: 6)
                Image(systemName: "heart")
                    .foregroundStyle(SomaTokens.accent)
                    .background(Image(systemName: "heart.fill").foregroundStyle(SomaTokens.accent.opacity(0.12)))
                    .scaleEffect(isPulsing ? 1.18 : 1.0)
                    .shadow(color: SomaTokens.accent.opacity(isPulsing ? 0.6 : 0.25), radius: isPulsing ? 5 : 2)
            }
            .frame(width: circleSize, height: circleSize)
            // Combine into a single element carrying the union of its
            // children's traits (including .image, from the heart glyph) --
            // otherwise this is a plain container and XCUITest's
            // app.images[a11yId] lookups (image-typed only) find nothing.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(a11yId)
        } else if isGoalDay, status == .done {
            heartDisc(fill: SomaTokens.successSoft, innerRing: nil, ring: SomaTokens.success.opacity(0.2)) {
                Image(systemName: "heart.fill").foregroundStyle(SomaTokens.success)
            }
            .shadow(color: SomaTokens.success.opacity(0.16), radius: 4, x: 0, y: 3)
            // Combine into a single element carrying the union of its
            // children's traits (including .image, from the heart glyph) --
            // otherwise this is a plain container and XCUITest's
            // app.images[a11yId] lookups (image-typed only) find nothing.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(a11yId)
        } else if status == .done {
            heartDisc(fill: SomaTokens.accentSoft10, innerRing: Color.white.opacity(0.85), ring: SomaTokens.hairline) {
                Image(systemName: "heart.fill").foregroundStyle(Self.heartDoneFill)
            }
            .shadow(color: SomaTokens.accent.opacity(0.14), radius: 4, x: 0, y: 3)
            // Combine into a single element carrying the union of its
            // children's traits (including .image, from the heart glyph) --
            // otherwise this is a plain container and XCUITest's
            // app.images[a11yId] lookups (image-typed only) find nothing.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(a11yId)
        } else if status == .skipped {
            // Missed/past -- the quietest state, deliberately no hairline.
            heartDisc(fill: Color.white.opacity(0.22), innerRing: nil, ring: Color.white.opacity(0.6)) {
                Image(systemName: "heart").foregroundStyle(SomaTokens.ink.opacity(0.16))
            }
            // Combine into a single element carrying the union of its
            // children's traits (including .image, from the heart glyph) --
            // otherwise this is a plain container and XCUITest's
            // app.images[a11yId] lookups (image-typed only) find nothing.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(a11yId)
        } else {
            // Planned (future, not yet happened) -- goal days get the same
            // treatment tinted green so an upcoming custom session is still
            // distinguishable from a plain planned day.
            let tint = isGoalDay ? SomaTokens.success : SomaTokens.accent
            heartDisc(fill: Color.white.opacity(0.35), innerRing: nil, ring: Color.white.opacity(0.8)) {
                Image(systemName: "heart").foregroundStyle(tint.opacity(0.35))
            }
            // Combine into a single element carrying the union of its
            // children's traits (including .image, from the heart glyph) --
            // otherwise this is a plain container and XCUITest's
            // app.images[a11yId] lookups (image-typed only) find nothing.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(a11yId)
        }
    }

    private func heartDisc(fill: Color, innerRing: Color?, ring: Color, @ViewBuilder icon: () -> some View) -> some View {
        ZStack {
            Circle().fill(fill)
            if let innerRing {
                Circle().strokeBorder(innerRing, lineWidth: 1)
                    .frame(width: circleSize - 3, height: circleSize - 3)
            }
            Circle().strokeBorder(ring, lineWidth: 1)
            icon().font(.system(size: 14))
        }
        .frame(width: circleSize, height: circleSize)
    }

    // MARK: - Best readiness

    /// The day among the current 7-day window with the highest recovery-
    /// band category. No longer shown as an inline crown glyph on the
    /// strip itself (not part of Soma Glass 3a) -- kept as a static
    /// lookup because `DayDetailView` still uses it for its own "Best
    /// readiness of the week" line. Most recent date wins ties.
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
