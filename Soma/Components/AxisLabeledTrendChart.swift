import SwiftUI

/// Labeled trend line -- y-axis min/max, x-axis first/last date, and an
/// optional dotted personal-average reference line. Wraps the existing
/// hand-rolled `TrendLineShape` (matching this app's established chart
/// style) rather than adopting a new charting library. Shared by
/// HealthDashboardView's Level 1 trend card and SingleMetricDetailView's
/// Level 3 deep dive, so both stay pixel-identical instead of two
/// hand-copied implementations drifting apart.
struct AxisLabeledTrendChart: View {
    let values: [(date: String, value: Double)]
    var showAverageLine = false
    var dateFormat = "MMM d"

    var body: some View {
        let rawValues = values.map(\.value)
        let minValue = rawValues.min() ?? 0
        let maxValue = rawValues.max() ?? 1
        let range = max(maxValue - minValue, 0.001)
        let average = rawValues.isEmpty ? nil : rawValues.reduce(0, +) / Double(rawValues.count)
        let points = values.enumerated().map { index, entry in
            CGPoint(
                x: values.count > 1 ? Double(index) / Double(values.count - 1) : 0.5,
                y: (entry.value - minValue) / range
            )
        }

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Self.formattedAxisValue(maxValue))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ZStack(alignment: .topLeading) {
                if showAverageLine, let average, range > 0 {
                    let averageY = 1 - (average - minValue) / range
                    GeometryReader { geometry in
                        Path { path in
                            let y = geometry.size.height * averageY
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(Theme.pillFill.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                TrendLineShape(points: points)
                    .stroke(Theme.pillFill, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(height: 60)
            HStack {
                Text(Self.formattedAxisValue(minValue))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Text(formattedAxisDate(values.first?.date))
                Spacer()
                Text(formattedAxisDate(values.last?.date))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    static func formattedAxisValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func formattedAxisDate(_ dateString: String?) -> String {
        guard let dateString else { return "" }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let parsed = parser.date(from: dateString) else { return dateString }
        let display = DateFormatter()
        display.dateFormat = dateFormat
        return display.string(from: parsed)
    }
}

#Preview {
    AxisLabeledTrendChart(
        values: (0..<14).map { i in (date: "2026-07-\(String(format: "%02d", i + 1))", value: Double.random(in: 40...90)) },
        showAverageLine: true
    )
    .padding()
}
