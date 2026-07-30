import SwiftUI

/// Apple-Watch-ring-style circular progress indicator for a single
/// 0...maxValue metric (Whoop recovery and Oura readiness are both already
/// treated as roughly 0-100 scales elsewhere in this app -- see
/// bandFromWhoop/bandFromOura in generate-recommendation/index.ts).
struct RingChartView: View {
    let value: Double
    let maxValue: Double
    let label: String
    var color: Color = Theme.pillFill
    var lineWidth: CGFloat = 14
    /// Default preserves every existing call site. Pass a smaller value
    /// (with a proportionally smaller lineWidth) to fit a denser layout,
    /// e.g. HealthDashboardView's 2-up metric grid.
    var diameter: CGFloat = 120

    private var fraction: Double {
        guard maxValue > 0 else { return 0 }
        return min(max(value / maxValue, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            VStack(spacing: 2) {
                Text(String(format: "%.0f", value))
                    .font(.title2.bold())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

#Preview {
    HStack(spacing: 20) {
        RingChartView(value: 78, maxValue: 100, label: "Recovery")
        RingChartView(value: 42, maxValue: 100, label: "Readiness")
    }
    .padding()
}
