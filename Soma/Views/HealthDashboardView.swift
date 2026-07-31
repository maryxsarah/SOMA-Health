import SwiftUI

/// Consolidated view of everything Soma already pulls from connected
/// wearables/HealthKit -- reachable from ProfileView. A denser 2-up grid,
/// one card per metric family with a real value today -- see
/// HealthMetricFamily's own doc comment for the full, deliberate list of
/// what's omitted vs. a richer reference design and why (no fabrication).
/// See TrainingHistoryView for the daily workout-by-workout list.
struct HealthDashboardView: View {
    @State private var todaysSnapshots: [DailySnapshotRow] = []
    @State private var recentSnapshots: [DailySnapshotRow] = []
    @State private var isLoading = true
    @State private var selectedMetricTitle: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                        todayCard
                        if !trendMetrics.isEmpty {
                            trendPickerCard
                        }
                        summaryCard
                    }
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle("Health Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HealthMetricFamily.self) { family in
                MetricDetailView(metric: family, recentSnapshots: recentSnapshots)
            }
        }
        .task { await load() }
    }

    /// Denser 2-up grid, one card per family with a real value today --
    /// replaces the old per-source ring+rows layout, which read like a
    /// data dump rather than the "quick, scannable overview" a Level 1
    /// should be. Every card uses the same style for visual consistency;
    /// Recovery/Readiness is distinguished by its qualitative pill
    /// (High/Medium/Low), not a different layout.
    private var todayCard: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(HealthMetricFamily.allCases) { family in
                if let value = todaysValue(for: family) {
                    metricCard(family: family, value: value)
                }
            }
        }
    }

    private func todaysValue(for family: HealthMetricFamily) -> Double? {
        todaysSnapshots.compactMap { family.value(from: $0) }.first
    }

    private func metricCard(family: HealthMetricFamily, value: Double) -> some View {
        let qualitativeLabel: String? = {
            guard family == .recoveryReadiness else { return nil }
            let isWhoopRecovery = todaysSnapshots.first { $0.recoveryScore != nil }?.recoveryScore != nil
            return HealthMetricFamily.qualitativeLabel(recoveryOrReadiness: value, isWhoopRecovery: isWhoopRecovery)
        }()
        let priorValues = dailyValues(for: family).dropLast().map(\.value)
        let trend = HealthMetricFamily.trendDescription(today: value, priorValues: Array(priorValues))
        return HealthMetricCardView(
            family: family,
            value: value,
            qualitativeLabel: qualitativeLabel,
            trend: trend,
            ringDiameter: family == .recoveryReadiness ? 64 : nil
        )
    }

    /// Pools whichever source(s) reported this metric per day -- same
    /// coalescing MetricDetailView's own dailyValues(for:) does.
    private func dailyValues(for family: HealthMetricFamily) -> [(date: String, value: Double)] {
        recentSnapshots.compactMap { row -> (String, Double)? in
            guard let value = family.value(from: row), let date = row.date else { return nil }
            return (date, value)
        }
    }

    private struct TrendMetric {
        let title: String
        let values: [(date: String, value: Double)]
    }

    /// One trend series per metric, pooling whichever source(s) reported
    /// it across the fetched range -- omitted entirely if nothing in the
    /// range ever reported that metric.
    private var trendMetrics: [TrendMetric] {
        func series(_ title: String, _ extract: (DailySnapshotRow) -> Double?) -> TrendMetric? {
            let values = recentSnapshots.compactMap { row -> (String, Double)? in
                guard let value = extract(row), let date = row.date else { return nil }
                return (date, value)
            }
            return values.isEmpty ? nil : TrendMetric(title: title, values: values)
        }
        return [
            series("Recovery / Readiness") { $0.recoveryScore ?? $0.readinessScore },
            series("HRV (ms)") { $0.hrvMs },
            series("Resting HR (bpm)") { $0.restingHr },
            series("Sleep (hours)") { $0.sleepHours },
            series("Strain") { $0.strainScore },
            series("Stress (min)") { $0.stressScore },
        ].compactMap { $0 }
    }

    /// One card: a metric picker (chip row) plus a single labeled trend for
    /// whichever metric is selected -- replaces the old "render every
    /// metric as its own full-width card" list, so the user picks what to
    /// look at instead of scrolling past six sparklines at once.
    private var trendPickerCard: some View {
        CardView {
            Text("Trends")
                .font(.body.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(trendMetrics, id: \.title) { metric in
                        metricChip(metric.title)
                    }
                }
            }
            if let selected = trendMetrics.first(where: { $0.title == effectiveSelectedTitle }) {
                trendCard(selected)
                    .padding(.top, 8)
            }
        }
    }

    private var effectiveSelectedTitle: String? {
        selectedMetricTitle ?? trendMetrics.first?.title
    }

    private func metricChip(_ title: String) -> some View {
        let isSelected = title == effectiveSelectedTitle
        return Button {
            selectedMetricTitle = title
        } label: {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? .white : Theme.pillFill)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Theme.pillFill : Theme.pillFill.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private func trendCard(_ metric: TrendMetric) -> some View {
        AxisLabeledTrendChart(values: metric.values)
    }

    /// Fixed, educational copy -- not personalized to today's numbers
    /// (that would risk implying a clinical read this app doesn't
    /// generate), just a plain explanation of what each metric is and why
    /// it's here, so a reader can build their own understanding of their
    /// data instead of only seeing raw numbers.
    private var summaryCard: some View {
        CardView {
            Text("What these mean")
                .font(.body.bold())
            summaryRow(
                title: "Recovery / Readiness",
                text: "A single score blending your heart rate variability, resting heart rate, and sleep from last night -- Whoop calls it Recovery, Oura calls it Readiness. Higher generally means your body is better prepared for a harder effort today."
            )
            summaryRow(
                title: "HRV (Heart Rate Variability)",
                text: "The variation in time between heartbeats. Generally, a higher HRV relative to your own baseline suggests your nervous system is well-recovered; a lower one can signal fatigue, stress, or incomplete recovery."
            )
            summaryRow(
                title: "Resting HR",
                text: "Your heart rate at rest, usually measured overnight. A notably higher-than-usual resting heart rate can be an early sign of accumulated fatigue, illness, or poor sleep."
            )
            summaryRow(
                title: "Sleep",
                text: "Total time asleep. Both duration and consistency matter for recovery -- see the sleep-stage breakdown on the Sleep detail page for how that time was split between light, deep, and REM sleep."
            )
            summaryRow(
                title: "Strain",
                text: "How much cardiovascular and muscular load your body has taken on. Whoop scores this 0-21; other sources report the count of harder sessions. Consistently high strain without matching recovery is what today's training caps (see \"Why today\" on your recommendation) are designed to catch."
            )
            summaryRow(
                title: "Stress",
                text: "Time spent in a high-stress physiological state today, as reported by Oura. This reflects the body's stress response generally, not necessarily how you feel emotionally."
            )
        }
    }

    private func summaryRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.bold())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
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

        todaysSnapshots = await todayFetch
        recentSnapshots = await recentFetch
        isLoading = false
    }
}

#Preview {
    HealthDashboardView()
}
