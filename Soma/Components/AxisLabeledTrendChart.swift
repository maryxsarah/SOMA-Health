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
                // Light horizontal gridlines (25/50/75%) -- a plain bare
                // line reads as a placeholder; gridlines are what make a
                // chart read as deliberately designed rather than
                // unfinished, at zero cost to the real data shown.
                GeometryReader { geometry in
                    ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                        Path { path in
                            let y = geometry.size.height * fraction
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(Color(.systemGray5), lineWidth: 1)
                    }
                }

                if showAverageLine, let average, range > 0 {
                    let averageY = 1 - (average - minValue) / range
                    GeometryReader { geometry in
                        Path { path in
                            let y = geometry.size.height * averageY
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(Theme.pillFill.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }

                // Filled area beneath the line -- same points TrendLineShape
                // draws, just closed down to the baseline and given a soft
                // gradient fill, the detail that makes a trend read as a
                // finished chart instead of "a line between 2 numbers."
                TrendAreaShape(points: points)
                    .fill(
                        LinearGradient(
                            colors: [Theme.pillFill.opacity(0.18), Theme.pillFill.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                TrendLineShape(points: points)
                    .stroke(Theme.pillFill, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Point markers -- every reading is a real, individually
                // meaningful data point (this app's data is at most daily
                // granularity, never a dense continuous series), so
                // marking each one is honest, not decorative. The most
                // recent point is emphasized since it's "today."
                GeometryReader { geometry in
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        let isLast = index == points.count - 1
                        Circle()
                            .fill(Theme.pillFill)
                            .frame(width: isLast ? 8 : 5, height: isLast ? 8 : 5)
                            .overlay(isLast ? Circle().stroke(.white, lineWidth: 1.5) : nil)
                            .position(x: geometry.size.width * point.x, y: geometry.size.height * (1 - point.y))
                    }
                }
            }
            .frame(height: 70)
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

/// Same point set/scaling as TrendLineShape (Soma/Components/OnboardingCharts.swift),
/// closed down to the bottom edge -- the shape a gradient fill needs.
/// Kept separate from TrendLineShape rather than modifying it, since that
/// shape is shared with onboarding's own (stroke-only) trend visuals.
private struct TrendAreaShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        func scale(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * rect.width, y: (1 - p.y) * rect.height)
        }
        path.move(to: CGPoint(x: scale(first).x, y: rect.height))
        path.addLine(to: scale(first))
        for point in points.dropFirst() {
            path.addLine(to: scale(point))
        }
        if let last = points.last {
            path.addLine(to: CGPoint(x: scale(last).x, y: rect.height))
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    AxisLabeledTrendChart(
        values: (0..<14).map { i in (date: "2026-07-\(String(format: "%02d", i + 1))", value: Double.random(in: 40...90)) },
        showAverageLine: true
    )
    .padding()
}
