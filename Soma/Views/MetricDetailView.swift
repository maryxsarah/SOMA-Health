import SwiftUI

/// Level 2 of the Health Dashboard's 3-level drill-down (Level 1 overview
/// -> Level 2 metric detail -> Level 3 single-metric deep dive). Shows a
/// day-strip history scroller, the restated score with a fixed template
/// insight sentence (never LLM-generated, matching this app's existing
/// "fixed, rule-based" copy convention), a Contributors section for
/// families that have real sub-inputs, and a Key Metrics grid whose rows
/// open Level 3.
struct MetricDetailView: View {
    let metric: HealthMetricFamily
    /// Passed down from HealthDashboardView -- already a 14-day window,
    /// which doubles as this level's day-strip history.
    let recentSnapshots: [DailySnapshotRow]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dayStrip
                scoreCard
                if !metric.contributors.isEmpty {
                    contributorsCard
                }
                keyMetricsCard
            }
            .padding(20)
        }
        .somaBackground()
        .navigationTitle(metric.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Scoped to this view (not the root HealthDashboardView) so a
        // HealthMetricFamily push FROM HERE (Key Metrics -> Level 3) is
        // caught by this closer destination instead of re-triggering
        // HealthDashboardView's own Level 1 -> Level 2 destination for the
        // same type -- SwiftUI resolves navigationDestination(for:) by the
        // nearest matching modifier in the active hierarchy, so nesting
        // one per level is the correct way to reuse HealthMetricFamily at
        // two different destinations.
        .navigationDestination(for: HealthMetricFamily.self) { family in
            SingleMetricDetailView(metric: family)
        }
    }

    /// Every day in the window that reported this metric, oldest to
    /// newest, as small tappable-free tiles -- swiping back through
    /// history without leaving the page.
    private var dayStrip: some View {
        let entries = dailyValues(for: metric)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(entries, id: \.date) { entry in
                    VStack(spacing: 4) {
                        Text(Self.shortDate(entry.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(AxisLabeledTrendChart.formattedAxisValue(entry.value))
                            .font(.caption.bold())
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.pillFill.opacity(0.08)))
                }
            }
        }
    }

    private var scoreCard: some View {
        CardView {
            let entries = dailyValues(for: metric)
            let today = entries.last
            HStack(alignment: .firstTextBaseline) {
                if let today {
                    Text(AxisLabeledTrendChart.formattedAxisValue(today.value))
                        .font(Theme.display)
                    if !metric.unit.isEmpty {
                        Text(metric.unit)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if metric == .recoveryReadiness, let today {
                    Text(HealthMetricFamily.qualitativeLabel(recoveryOrReadiness: today.value, isWhoopRecovery: isWhoopSource))
                        .font(.caption.bold())
                        .foregroundStyle(Theme.pillFill)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.pillFill.opacity(0.12)))
                }
            }
            Text(insightSentence(entries: entries))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    /// Fixed template, never LLM-generated -- compares today's value
    /// against the trailing average, same "plain arithmetic + a fixed
    /// sentence" approach as RecommendationCategory's messages.
    private func insightSentence(entries: [(date: String, value: Double)]) -> String {
        guard let today = entries.last else {
            return "Not enough data yet to show a trend for \(metric.displayTitle.lowercased())."
        }
        let priorEntries = entries.dropLast()
        guard !priorEntries.isEmpty else {
            return "This is your first recorded reading for \(metric.displayTitle.lowercased())."
        }
        let average = priorEntries.map(\.value).reduce(0, +) / Double(priorEntries.count)
        let diffPercent = average != 0 ? (today.value - average) / average * 100 : 0
        if abs(diffPercent) < 5 {
            return "Today's \(metric.displayTitle.lowercased()) is in line with your recent average."
        } else if diffPercent > 0 {
            return "Today's \(metric.displayTitle.lowercased()) is about \(Int(abs(diffPercent)))% above your recent average."
        } else {
            return "Today's \(metric.displayTitle.lowercased()) is about \(Int(abs(diffPercent)))% below your recent average."
        }
    }

    private var contributorsCard: some View {
        CardView {
            Text("Contributors")
                .font(.body.bold())
            Text("The real signals behind today's \(metric.displayTitle.lowercased()) read.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(metric.contributors) { contributor in
                contributorRow(contributor)
            }
        }
    }

    private func contributorRow(_ contributor: HealthMetricFamily) -> some View {
        let entries = dailyValues(for: contributor)
        let today = entries.last?.value
        let allValues = entries.map(\.value)
        let minValue = allValues.min() ?? 0
        let maxValue = allValues.max() ?? 1
        let range = max(maxValue - minValue, 0.001)
        let position = today.map { min(max(($0 - minValue) / range, 0), 1) }

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(contributor.displayTitle)
                    .font(.subheadline)
                Spacer()
                if let today {
                    Text("\(AxisLabeledTrendChart.formattedAxisValue(today))\(contributor.unit.isEmpty ? "" : contributor.unit)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.pillFill.opacity(0.12)).frame(height: 6)
                    if let position {
                        Circle()
                            .fill(Theme.pillFill)
                            .frame(width: 10, height: 10)
                            .offset(x: geometry.size.width * position - 5)
                    }
                }
            }
            .frame(height: 10)
        }
        .padding(.top, 6)
    }

    private var keyMetricsCard: some View {
        CardView {
            Text("Key Metrics")
                .font(.body.bold())
            let items = metric.contributors.isEmpty ? [metric] : metric.contributors
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let value = dailyValues(for: item).last?.value {
                                Text("\(AxisLabeledTrendChart.formattedAxisValue(value))\(item.unit.isEmpty ? "" : item.unit)")
                                    .font(.title3.bold())
                            } else {
                                Text("--")
                                    .font(.title3.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.pillFill.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Pools whichever source(s) reported this metric per day -- same
    /// coalescing HealthDashboardView's trendMetrics already does.
    private func dailyValues(for family: HealthMetricFamily) -> [(date: String, value: Double)] {
        recentSnapshots.compactMap { row -> (String, Double)? in
            guard let value = family.value(from: row), let date = row.date else { return nil }
            return (date, value)
        }
    }

    private var isWhoopSource: Bool {
        recentSnapshots.last { $0.recoveryScore != nil || $0.readinessScore != nil }?.recoveryScore != nil
    }

    private static func shortDate(_ dateString: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let parsed = parser.date(from: dateString) else { return dateString }
        let display = DateFormatter()
        display.dateFormat = "M/d"
        return display.string(from: parsed)
    }
}

#Preview {
    NavigationStack {
        MetricDetailView(metric: .recoveryReadiness, recentSnapshots: [])
    }
}
