import SwiftUI

/// Level 3 of the Health Dashboard's 3-level drill-down: a single raw
/// metric's deep dive, with a Day/Week/Month/Year range control. Reuses
/// AxisLabeledTrendChart (shared with Level 1's trend card) so this and
/// the overview chart never visually drift apart.
struct SingleMetricDetailView: View {
    let metric: HealthMetricFamily

    private enum TrendRange: String, CaseIterable, Identifiable {
        case day, week, month, year
        var id: String { rawValue }
        var displayTitle: String { rawValue.capitalized }

        /// How many days back fetchSnapshots(fromDate:toDate:) should
        /// request -- the schema itself has no retention cap, only Level 1
        /// ever asked for more than 14 days before this view existed.
        var lookbackDays: Int {
            switch self {
            case .day: 1
            case .week: 7
            case .month: 30
            case .year: 365
            }
        }
    }

    @State private var range: TrendRange = .week
    @State private var snapshots: [DailySnapshotRow] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { r in
                        Text(r.displayTitle).tag(r)
                    }
                }
                .pickerStyle(.segmented)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                } else {
                    let values = dailyValues
                    if let latest = values.last {
                        Text("\(AxisLabeledTrendChart.formattedAxisValue(latest.value))\(metric.unit.isEmpty ? "" : metric.unit)")
                            .font(Theme.display)
                    }

                    // daily_snapshot is day-granularity only -- there is no
                    // intraday time series in this app's data model, so
                    // "Day" view has nothing to chart. Rather than fake an
                    // hourly breakdown, say so plainly and point at the
                    // ranges that do have real data.
                    if range == .day {
                        CardView {
                            Text("Day view shows today's single reading above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Switch to Week, Month, or Year for a trend -- this app records one \(metric.displayTitle.lowercased()) reading per day, not an intraday series.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if values.isEmpty {
                        CardView {
                            Text("No data yet")
                                .font(.body.bold())
                            Text("Nothing recorded for \(metric.displayTitle.lowercased()) in this range.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if values.count == 1 {
                        CardView {
                            Text("Only one data point so far")
                                .font(.body.bold())
                            Text("Check back once you have a few more days of \(metric.displayTitle.lowercased()) recorded.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        CardView {
                            AxisLabeledTrendChart(values: values, showAverageLine: true, dateFormat: range == .year ? "MMM ''yy" : "MMM d")
                        }
                    }
                }
            }
            .padding(20)
        }
        .somaBackground()
        .navigationTitle(metric.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) { await load() }
    }

    private var dailyValues: [(date: String, value: Double)] {
        snapshots.compactMap { row -> (String, Double)? in
            guard let value = metric.value(from: row), let date = row.date else { return nil }
            return (date, value)
        }
    }

    private func load() async {
        isLoading = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let today = Date()
        let start = Calendar.current.date(byAdding: .day, value: -range.lookbackDays, to: today) ?? today

        snapshots = (try? await SupabaseClient.shared.fetchSnapshots(
            fromDate: formatter.string(from: start),
            toDate: formatter.string(from: today)
        )) ?? []
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        SingleMetricDetailView(metric: .hrv)
    }
}
