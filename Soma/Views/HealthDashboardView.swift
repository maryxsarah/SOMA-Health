import SwiftUI

/// Health dashboard, rebuilt per handoff guide 08: four sections
/// (Overview / Sleep / Activity / Body) as chips, each fitting one screen --
/// hero ring card, sparkline metric rows, a trend chart, and a "What these
/// mean" accordion (one open at a time). Sections only ever show metrics a
/// connected source actually reported -- no fabricated numbers, same
/// standing rule as HealthMetricFamily. No bottom nav (SELF-CHECK: sections
/// live at the top). See TrainingHistoryView for the workout-by-workout list.
struct HealthDashboardView: View {
    @State private var todaysSnapshots: [DailySnapshotRow] = []
    @State private var recentSnapshots: [DailySnapshotRow] = []
    @State private var completedDates: Set<String> = []
    @State private var profile: UserProfile?
    @State private var recentMoods: [DailyMoodEntry] = []
    @State private var isLoading = true
    @State private var selectedSection: DashboardSection = .overview
    @State private var openAccordionTitle: String?

    private enum DashboardSection: String, CaseIterable, Identifiable {
        case overview, sleep, activity, body

        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: "Overview"
            case .sleep: "Sleep"
            case .activity: "Activity"
            case .body: "Body"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if todaysSnapshots.isEmpty && recentSnapshots.isEmpty {
                        CardView {
                            Text("No health data yet")
                                .font(.body.bold())
                            Text("Connect a wearable or Apple Health to see your metrics here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        sectionMenu
                        sectionBody
                    }
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle("Your health")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HealthMetricFamily.self) { family in
                MetricDetailView(metric: family, recentSnapshots: recentSnapshots)
            }
        }
        .task { await load() }
    }

    // MARK: - Section menu (guide 08: four chips, equal flex)

    private var sectionMenu: some View {
        HStack(spacing: 8) {
            ForEach(DashboardSection.allCases) { section in
                let isSelected = section == selectedSection
                Button {
                    selectedSection = section
                    openAccordionTitle = nil
                } label: {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? SomaTokens.accent : SomaTokens.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous)
                                .fill(isSelected ? SomaTokens.accentSoft : SomaTokens.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous)
                                .strokeBorder(isSelected ? SomaTokens.accent : SomaTokens.hairline, lineWidth: isSelected ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch selectedSection {
        case .overview: overviewSection
        case .sleep: sleepSection
        case .activity: activitySection
        case .body: bodySection
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewSection: some View {
        if let score = todaysValue({ $0.recoveryScore ?? $0.readinessScore }) {
            let isWhoop = todaysSnapshots.contains { $0.recoveryScore != nil }
            heroCard(
                ringValue: score, ringMax: 100, ringText: String(Int(score.rounded())), ringUnit: isWhoop ? "RECOVERY" : "READINESS",
                eyebrow: "TODAY'S READ",
                headline: overviewHeadline(score: score, isWhoop: isWhoop),
                context: bestInRangeContext(values: seriesValues { $0.recoveryScore ?? $0.readinessScore }, current: score)
            )
        }

        metricRowsCard(rows: [
            metricRow(family: .sleep, label: "Sleep", unit: "h", format: "%.1f", upIsGood: true) { $0.sleepHours },
            metricRow(family: .hrv, label: "HRV", unit: "ms", format: "%.0f", upIsGood: true) { $0.hrvMs },
            metricRow(family: .restingHR, label: "Resting HR", unit: "bpm", format: "%.0f", upIsGood: false) { $0.restingHr },
        ])

        trendCard(title: "Recovery", series: series { $0.recoveryScore ?? $0.readinessScore }, format: "%.0f")

        moodTrendCard

        accordionCard(items: [
            ("Recovery / Readiness", todaysValueText(format: "%.0f", unit: "") { $0.recoveryScore ?? $0.readinessScore }, "A single score blending your heart rate variability, resting heart rate, and sleep from last night -- Whoop calls it Recovery, Oura calls it Readiness. Higher generally means your body is better prepared for a harder effort today."),
            ("HRV", todaysValueText(format: "%.0f", unit: " ms") { $0.hrvMs }, "The variation in time between heartbeats. Generally, a higher HRV relative to your own baseline suggests your nervous system is well-recovered; a lower one can signal fatigue, stress, or incomplete recovery."),
            ("Resting HR", todaysValueText(format: "%.0f", unit: " bpm") { $0.restingHr }, "Your heart rate at rest, usually measured overnight. A notably higher-than-usual resting heart rate can be an early sign of accumulated fatigue, illness, or poor sleep."),
            ("Sleep", todaysValueText(format: "%.1f", unit: " h") { $0.sleepHours }, "Total time asleep. Both duration and consistency matter for recovery -- see the Sleep section for how that time was split between light, deep, and REM sleep."),
        ])
    }

    private func overviewHeadline(score: Double, isWhoop: Bool) -> String {
        switch HealthMetricFamily.qualitativeBand(recoveryOrReadiness: score, isWhoopRecovery: isWhoop) {
        case .high: return "High — a good day to push"
        case .mediumHigh: return "Medium-High — quality work fits today"
        case .medium: return "Medium — moderate effort fits"
        case .low: return "Low — favor recovery today"
        }
    }

    // MARK: - Sleep

    @ViewBuilder
    private var sleepSection: some View {
        if let hours = todaysValue({ $0.sleepHours }) {
            // Ring is relative to a fixed 8h reference, and labeled as such --
            // a reference, not a claim about this user's personal need.
            heroCard(
                ringValue: min(hours, 8), ringMax: 8, ringText: String(format: "%.1f", hours), ringUnit: "OF 8 H",
                eyebrow: "LAST NIGHT",
                headline: hours >= 7 ? "Solid night's sleep" : "Shorter than ideal",
                context: averageDeltaContext(values: seriesValues { $0.sleepHours }, current: hours, unit: " h", format: "%+.1f")
            )
        } else {
            CardView {
                Text("No sleep recorded last night")
                    .font(.body.bold())
                Text("Wear your device overnight to see sleep here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        metricRowsCard(rows: [
            metricRow(family: .sleep, label: "Deep", unit: "h", format: "%.1f", upIsGood: true) { $0.sleepDeepHours },
            metricRow(family: .sleep, label: "REM", unit: "h", format: "%.1f", upIsGood: true) { $0.sleepRemHours },
            metricRow(family: .sleep, label: "Awake", unit: "h", format: "%.1f", upIsGood: false) { $0.sleepAwakeHours },
        ])

        let stageEntries = sleepStageEntries
        if !stageEntries.isEmpty {
            CardView {
                Text("Sleep stages")
                    .font(.body.bold())
                SleepStageBarChart(entries: stageEntries)
            }
        }

        trendCard(title: "Sleep duration", series: series { $0.sleepHours }, format: "%.1f")
    }

    /// Last 7 days that actually carry a stage breakdown -- days without
    /// one simply don't render a bar (no fabricated splits).
    private var sleepStageEntries: [SleepStageBarChart.Entry] {
        recentSnapshots
            .filter { $0.sleepDeepHours != nil || $0.sleepRemHours != nil || $0.sleepLightHours != nil }
            .suffix(7)
            .compactMap { row in
                guard let date = row.date else { return nil }
                return SleepStageBarChart.Entry(date: date, light: row.sleepLightHours, deep: row.sleepDeepHours, rem: row.sleepRemHours, awake: row.sleepAwakeHours)
            }
    }

    // MARK: - Activity

    @ViewBuilder
    private var activitySection: some View {
        let target = max(profile?.weeklySessionTarget ?? 5, 1)
        let done = completedDates.count
        heroCard(
            ringValue: Double(min(done, target)), ringMax: Double(target), ringText: "\(done)", ringUnit: "OF \(target)",
            eyebrow: "SESSIONS THIS WEEK",
            headline: done >= target ? "Weekly target hit" : "\(target - done) to go this week",
            context: nil
        )

        metricRowsCard(rows: [
            metricRow(family: .strain, label: "Strain", unit: "", format: "%.1f", upIsGood: false) { $0.strainScore },
            metricRow(family: .stress, label: "High stress", unit: "min", format: "%.0f", upIsGood: false) { $0.stressScore },
        ])

        trendCard(title: "Strain", series: series { $0.strainScore }, format: "%.1f")

        accordionCard(items: [
            ("Strain", todaysValueText(format: "%.1f", unit: "") { $0.strainScore }, "How much cardiovascular and muscular load your body has taken on. Whoop scores this 0-21; other sources report the count of harder sessions. Consistently high strain without matching recovery is what today's training caps are designed to catch."),
            ("Stress", todaysValueText(format: "%.0f", unit: " min") { $0.stressScore }, "Time spent in a high-stress physiological state today, as reported by Oura. This reflects the body's stress response generally, not necessarily how you feel emotionally."),
        ])
    }

    // MARK: - Body

    @ViewBuilder
    private var bodySection: some View {
        if let weight = profile?.weightKg {
            CardView {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", weight))
                        .font(.system(size: 34, design: .serif).italic())
                    Text("KG")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SomaTokens.ink4)
                }
                if let goal = profile?.desiredWeightKg {
                    let delta = weight - goal
                    Text(abs(delta) < 0.05
                        ? "At your goal weight"
                        : String(format: "%.1f kg %@ your goal of %.1f kg", abs(delta), delta > 0 ? "above" : "below", goal))
                        .font(.system(size: 13))
                        .foregroundStyle(SomaTokens.ink2)
                }
                Text("From your profile — Soma doesn't track weight over time yet.")
                    .font(.caption)
                    .foregroundStyle(SomaTokens.ink4)
            }

            if let bmi = BodyMetrics.bmi(weightKg: weight, heightCm: profile?.heightCm) {
                CardView {
                    HStack(alignment: .firstTextBaseline) {
                        Text("BMI")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(String(format: "%.1f", bmi))
                            .font(.system(size: 22, design: .serif).italic())
                    }
                    Text(BodyMetrics.bmiCategory(bmi))
                        .font(.caption.bold())
                        .foregroundStyle(SomaTokens.ink2)
                    Text("A general population screening measure, not a fitness or body-composition score -- it doesn't distinguish muscle from fat.")
                        .font(.caption2)
                        .foregroundStyle(SomaTokens.ink4)
                }
            }

            if let journey = GoalJourneyProgress.compute(
                createdAt: profile?.createdAt,
                weightKg: profile?.weightKg,
                desiredWeightKg: profile?.desiredWeightKg,
                goalPace: profile?.goalPace
            ) {
                CardView {
                    Text("Progress toward your goal")
                        .font(.subheadline.bold())
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(SomaTokens.surface3)
                            Capsule()
                                .fill(SomaTokens.accent)
                                .frame(width: max(0, geo.size.width * journey.fraction))
                        }
                    }
                    .frame(height: 10)
                    .clipShape(Capsule())
                    Text("Day \(journey.daysElapsed) of roughly \(journey.estimatedTotalDays), at your chosen pace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            CardView {
                Text("No body data yet")
                    .font(.body.bold())
                Text("Your weight from onboarding shows here once set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Shared cards

    private func heroCard(ringValue: Double, ringMax: Double, ringText: String, ringUnit: String, eyebrow: String, headline: String, context: String?) -> some View {
        CardView {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color(red: 0.929, green: 0.945, blue: 0.973), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: ringMax > 0 ? min(max(ringValue / ringMax, 0), 1) : 0)
                        .stroke(SomaTokens.accentDeep, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(ringText)
                            .font(.system(size: 26, design: .serif).italic())
                        Text(ringUnit)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(SomaTokens.ink4)
                    }
                }
                .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(SomaTokens.ink4)
                    Text(headline)
                        .font(.system(size: 19, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let context {
                        HStack(spacing: 5) {
                            Circle().fill(SomaTokens.successDot).frame(width: 6, height: 6)
                            Text(context)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(SomaTokens.success)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(SomaTokens.successSoft))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private struct MetricRowModel: Identifiable {
        let id: String
        let family: HealthMetricFamily
        let row: SomaSparklineRow
    }

    /// Nil when the metric has no data at all in the fetched range --
    /// the row simply doesn't render.
    private func metricRow(family: HealthMetricFamily, label: String, unit: String, format: String, upIsGood: Bool, _ extract: @escaping (DailySnapshotRow) -> Double?) -> MetricRowModel? {
        let values = seriesValues(extract)
        guard let current = values.last else { return nil }
        var deltaText: String?
        var deltaIsGood = false
        let prior = values.dropLast()
        if !prior.isEmpty {
            let avg = prior.reduce(0, +) / Double(prior.count)
            let change = avg == 0 ? 0 : (current - avg) / avg * 100
            if abs(change) < 3 {
                deltaText = "steady"
            } else {
                deltaText = String(format: "%@ %.0f%%", change > 0 ? "↑" : "↓", abs(change))
                deltaIsGood = (change > 0) == upIsGood
            }
        }
        let valueText = "\(String(format: format, current))\(unit.isEmpty ? "" : " \(unit)")"
        return MetricRowModel(
            id: label,
            family: family,
            row: SomaSparklineRow(label: label, valueText: valueText, series: values, deltaText: deltaText, deltaIsGood: deltaIsGood)
        )
    }

    @ViewBuilder
    private func metricRowsCard(rows: [MetricRowModel?]) -> some View {
        let present = rows.compactMap { $0 }
        if !present.isEmpty {
            CardView {
                ForEach(Array(present.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        Divider().overlay(SomaTokens.surface4)
                    }
                    NavigationLink(value: model.family) {
                        model.row
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func trendCard(title: String, series values: [(date: String, value: Double)], format: String) -> some View {
        if values.count > 1 {
            let raw = values.map(\.value)
            let avg = raw.reduce(0, +) / Double(raw.count)
            let lo = raw.min() ?? 0
            let hi = raw.max() ?? 0
            CardView {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.body.bold())
                    Spacer()
                    Text("avg \(String(format: format, avg)) · range \(String(format: format, lo))–\(String(format: format, hi))")
                        .font(.caption)
                        .foregroundStyle(SomaTokens.ink3)
                }
                AxisLabeledTrendChart(values: values, showAverageLine: true)
            }
        }
    }

    /// Real feedback: "some human-level metric that the app optimizes ...
    /// showing that the metric improves with app usage." Home's daily
    /// check-in card feeds this -- shown only once there's more than one
    /// day logged (a single point has no trend to draw).
    @ViewBuilder
    private var moodTrendCard: some View {
        if recentMoods.count > 1 {
            let values = recentMoods.map { (date: $0.date, value: Double($0.rating)) }
            CardView {
                Text("How you've been feeling")
                    .font(.body.bold())
                AxisLabeledTrendChart(values: values, showAverageLine: true)
                if let comparison = Self.moodComparisonText(recentMoods) {
                    Text(comparison)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.ink3)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Splits the logged range in half and compares averages -- real
    /// numbers only, never a fabricated "you're improving!" line. Needs
    /// at least 3 entries on each side to say anything meaningful; below
    /// that the chart speaks for itself with no added sentence.
    private static func moodComparisonText(_ moods: [DailyMoodEntry]) -> String? {
        guard moods.count >= 6 else { return nil }
        let midpoint = moods.count / 2
        let earlier = moods.prefix(midpoint)
        let recent = moods.suffix(moods.count - midpoint)
        guard !earlier.isEmpty, !recent.isEmpty else { return nil }
        let earlierAvg = Double(earlier.reduce(0) { $0 + $1.rating }) / Double(earlier.count)
        let recentAvg = Double(recent.reduce(0) { $0 + $1.rating }) / Double(recent.count)
        let delta = recentAvg - earlierAvg
        if abs(delta) < 0.3 {
            return "Holding steady around \(String(format: "%.1f", recentAvg))/5 lately."
        }
        return delta > 0
            ? "Averaging \(String(format: "%.1f", recentAvg))/5 lately, up from \(String(format: "%.1f", earlierAvg))/5 earlier."
            : "Averaging \(String(format: "%.1f", recentAvg))/5 lately, down from \(String(format: "%.1f", earlierAvg))/5 earlier."
    }

    /// Guide 08's "What these mean": one open at a time, collapsed rows
    /// still show their value so the section is useful even shut.
    private func accordionCard(items: [(title: String, value: String?, text: String)]) -> some View {
        CardView {
            Text("What these mean")
                .font(.body.bold())
            ForEach(Array(items.enumerated()), id: \.element.title) { index, item in
                if index > 0 {
                    Divider().overlay(SomaTokens.surface4)
                }
                let isOpen = openAccordionTitle == item.title
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            openAccordionTitle = isOpen ? nil : item.title
                        }
                    } label: {
                        HStack {
                            Text(item.title)
                                .font(.system(size: 13.5, weight: .semibold))
                            Spacer()
                            if let value = item.value {
                                Text(value)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SomaTokens.ink3)
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(SomaTokens.ink4)
                                .rotationEffect(.degrees(isOpen ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isOpen {
                        Text(item.text)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .foregroundStyle(SomaTokens.ink2)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous)
                                    .fill(SomaTokens.surface3)
                            )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Data helpers

    /// Strictly today's snapshots -- no fallback to older days, because every
    /// caller labels the result as current ("TODAY'S READ", "LAST NIGHT").
    private func todaysValue(_ extract: (DailySnapshotRow) -> Double?) -> Double? {
        todaysSnapshots.compactMap(extract).first
    }

    private func todaysValueText(format: String, unit: String, _ extract: (DailySnapshotRow) -> Double?) -> String? {
        todaysValue(extract).map { "\(String(format: format, $0))\(unit)" }
    }

    /// Per-day series pooling whichever source(s) reported the metric,
    /// chronological (the fetch orders date.asc).
    private func series(_ extract: (DailySnapshotRow) -> Double?) -> [(date: String, value: Double)] {
        recentSnapshots.compactMap { row in
            guard let value = extract(row), let date = row.date else { return nil }
            return (date, value)
        }
    }

    private func seriesValues(_ extract: (DailySnapshotRow) -> Double?) -> [Double] {
        series(extract).map(\.value)
    }

    private func bestInRangeContext(values: [Double], current: Double) -> String? {
        guard values.count > 2, current >= (values.max() ?? current) else { return nil }
        return "Best in \(values.count) days"
    }

    private func averageDeltaContext(values: [Double], current: Double, unit: String, format: String) -> String? {
        let prior = values.dropLast()
        guard !prior.isEmpty else { return nil }
        let avg = prior.reduce(0, +) / Double(prior.count)
        let delta = current - avg
        guard delta > 0 else { return nil }
        return "\(String(format: format, delta))\(unit) vs your average"
    }

    private func load() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let today = formatter.string(from: Date())
        let start = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()

        async let todayFetch: [DailySnapshotRow] = (try? await SupabaseClient.shared.fetchTodaysSnapshots(date: today)) ?? []
        async let recentFetch: [DailySnapshotRow] = (try? await SupabaseClient.shared.fetchSnapshots(
            fromDate: formatter.string(from: start),
            toDate: today
        )) ?? []
        async let completedFetch: Set<String> = (try? await SupabaseClient.shared.fetchRecentWorkoutLogDates()) ?? []
        async let profileFetch: UserProfile? = {
            guard let userId = SupabaseClient.shared.currentUserID else { return nil }
            return try? await SupabaseClient.shared.fetchProfile(id: userId)
        }()
        async let moodsFetch: [DailyMoodEntry] = (try? await SupabaseClient.shared.fetchRecentMoods(days: 30)) ?? []

        todaysSnapshots = await todayFetch
        recentSnapshots = await recentFetch
        completedDates = await completedFetch
        profile = await profileFetch
        recentMoods = await moodsFetch
        isLoading = false
    }
}

#Preview {
    HealthDashboardView()
}
