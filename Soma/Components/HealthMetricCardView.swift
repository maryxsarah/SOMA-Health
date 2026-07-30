import SwiftUI

/// Denser 2-up grid tile for HealthDashboardView's Level 1 -- title, big
/// number, and (Recovery/Readiness only) a qualitative pill, wrapped in a
/// NavigationLink so the existing `.navigationDestination(for:
/// HealthMetricFamily.self)` on the root NavigationStack keeps working
/// unmodified. Reuses Theme's existing tokens only -- no new colors.
struct HealthMetricCardView: View {
    let family: HealthMetricFamily
    let value: Double?
    let qualitativeLabel: String?
    /// Nil when there isn't enough history to compare against -- shown as
    /// no trend indicator rather than a fabricated flat one.
    let trend: (percent: Int, direction: HealthMetricFamily.TrendDirection)?
    /// Non-nil only for Recovery/Readiness -- this app's one existing
    /// "headline" metric keeps a small ring visual (RingChartView, shrunk
    /// to fit this denser card) instead of the plain number every other
    /// family uses, so it stays visually distinguished without a
    /// different card layout.
    var ringDiameter: CGFloat? = nil

    var body: some View {
        NavigationLink(value: family) {
            CardView {
                HStack {
                    Text(family.displayTitle)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let value, let ringDiameter {
                    // Empty label: the card's own title above already
                    // names the metric, no need to repeat it inside the ring.
                    RingChartView(value: value, maxValue: 100, label: "", lineWidth: 8, diameter: ringDiameter)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(AxisLabeledTrendChart.formattedAxisValue(value))
                            .font(Theme.display)
                        if !family.unit.isEmpty {
                            Text(family.unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("--")
                        .font(Theme.display)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if let qualitativeLabel {
                        Text(qualitativeLabel)
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.pillFill)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.pillFill.opacity(0.12)))
                    }
                    if let trend, trend.direction != .flat {
                        Label(
                            "\(trend.percent)%",
                            systemImage: trend.direction == .up ? "arrow.up" : "arrow.down"
                        )
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        HealthMetricCardView(family: .recoveryReadiness, value: 78, qualitativeLabel: "High", trend: (12, .up))
        HealthMetricCardView(family: .sleep, value: 7.2, qualitativeLabel: nil, trend: (4, .flat))
    }
    .padding()
    .somaBackground()
}
