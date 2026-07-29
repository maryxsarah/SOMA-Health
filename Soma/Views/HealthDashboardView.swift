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
                        ForEach(trendMetrics, id: \.title) { metric in
                            trendCard(metric)
                        }
                    }
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle("Health Dashboard")
            .navigationBarTitleDisplayMode(.inline)
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
                    ForEach(metricLines(for: snapshot), id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    /// Only lines with a real value -- a source that doesn't report a
    /// metric (e.g. Whoop has no stress score) simply contributes nothing,
    /// rather than showing a placeholder.
    private func metricLines(for snapshot: DailySnapshotRow) -> [String] {
        var lines: [String] = []
        if let recovery = snapshot.recoveryScore { lines.append("Recovery: \(Int(recovery))%") }
        if let readiness = snapshot.readinessScore { lines.append("Readiness: \(Int(readiness))") }
        if let hrv = snapshot.hrvMs { lines.append("HRV: \(Int(hrv))ms") }
        if let restingHr = snapshot.restingHr { lines.append("Resting HR: \(Int(restingHr))bpm") }
        if let sleepHours = snapshot.sleepHours { lines.append("Sleep: \(String(format: "%.1f", sleepHours))h") }
        if let strain = snapshot.strainScore {
            lines.append(snapshot.source == "whoop" ? "Strain: \(String(format: "%.1f", strain))/21" : "Strain: \(Int(strain)) hard session(s)")
        }
        if let stress = snapshot.stressScore { lines.append("Stress: \(Int(stress)) min high-stress today") }
        return lines
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

    private func trendCard(_ metric: TrendMetric) -> some View {
        CardView {
            Text(metric.title)
                .font(.body.bold())
            let values = metric.values.map(\.value)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let range = max(maxValue - minValue, 0.001)
            let points = metric.values.enumerated().map { index, entry in
                CGPoint(
                    x: metric.values.count > 1 ? Double(index) / Double(metric.values.count - 1) : 0.5,
                    y: (entry.value - minValue) / range
                )
            }
            TrendLineShape(points: points)
                .stroke(Theme.pillFill, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(height: 60)
                .padding(.top, 4)
        }
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
