import SwiftUI

/// Consolidated view of everything Soma already pulls from connected
/// wearables/HealthKit -- reachable from ProfileView. Deliberately shows
/// only metrics with a real data source today (Recovery, Readiness, HRV,
/// resting HR, sleep hours, strain, stress, workout summary). Health Age
/// vs Actual Age, cycle day, body composition, weight trend, and
/// sleep-stage breakdown have no data source in this app or from
/// Whoop/Oura/HealthKit today and are intentionally omitted rather than
/// faked -- see TrainingHistoryView for the daily workout-by-workout list.
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

    private var todayCard: some View {
        CardView {
            Text("Today")
                .font(.body.bold())
            ForEach(todaysSnapshots, id: \.source) { snapshot in
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.source.capitalized)
                        .font(.caption.bold())
                        .foregroundStyle(Theme.pillFill)
                    HStack(alignment: .top, spacing: 16) {
                        // Recovery (Whoop, 0-100) and readiness (Oura, 0-100)
                        // are both already treated as roughly the same scale
                        // elsewhere in this app (bandFromWhoop/bandFromOura),
                        // so one ring covers whichever this source reports.
                        if let primary = snapshot.recoveryScore ?? snapshot.readinessScore {
                            NavigationLink(value: HealthMetricFamily.recoveryReadiness) {
                                RingChartView(
                                    value: primary,
                                    maxValue: 100,
                                    label: snapshot.recoveryScore != nil ? "Recovery" : "Readiness"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(metricLineRows(for: snapshot), id: \.family) { row in
                                NavigationLink(value: row.family) {
                                    HStack {
                                        Text(row.text)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private struct MetricLineRow {
        let family: HealthMetricFamily
        let text: String
    }

    /// Only rows with a real value -- a source that doesn't report a
    /// metric (e.g. Whoop has no stress score) simply contributes nothing,
    /// rather than showing a placeholder. Recovery/readiness are shown as
    /// the ring above instead of repeating them here. Each row is tappable
    /// -- Level 1 -> Level 2 (MetricDetailView).
    private func metricLineRows(for snapshot: DailySnapshotRow) -> [MetricLineRow] {
        var rows: [MetricLineRow] = []
        if let hrv = snapshot.hrvMs { rows.append(.init(family: .hrv, text: "HRV: \(Int(hrv))ms")) }
        if let restingHr = snapshot.restingHr { rows.append(.init(family: .restingHR, text: "Resting HR: \(Int(restingHr))bpm")) }
        if let sleepHours = snapshot.sleepHours { rows.append(.init(family: .sleep, text: "Sleep: \(String(format: "%.1f", sleepHours))h")) }
        if let strain = snapshot.strainScore {
            let text = snapshot.source == "whoop" ? "Strain: \(String(format: "%.1f", strain))/21" : "Strain: \(Int(strain)) hard session(s)"
            rows.append(.init(family: .strain, text: text))
        }
        if let stress = snapshot.stressScore { rows.append(.init(family: .stress, text: "Stress: \(Int(stress)) min high-stress today")) }
        return rows
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
