import SwiftUI

/// Straight-segment line through normalized points (x: 0...1, y: 0...1,
/// where y=1 is the top of the drawing rect). Used with `.trim(from:to:)`
/// for the draw-in animation on every trend chart below.
struct TrendLineShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        func scale(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * rect.width, y: (1 - p.y) * rect.height)
        }
        path.move(to: scale(first))
        for point in points.dropFirst() {
            path.addLine(to: scale(point))
        }
        return path
    }
}

/// Single upward trend line -- "you're right on track" (survey) and the
/// plan-summary screen both reuse this.
struct UpwardTrendChartView: View {
    var xAxisLabels: [String] = ["3 Days", "7 Days", "30 Days"]
    /// Compact call sites (e.g. the welcome screen, which must fit without
    /// scrolling) pass a shorter height than the default.
    var chartHeight: CGFloat = 160
    @State private var drawProgress: CGFloat = 0
    @State private var showBadge = false

    private let points: [CGPoint] = [
        CGPoint(x: 0, y: 0.15), CGPoint(x: 0.33, y: 0.35), CGPoint(x: 0.66, y: 0.6), CGPoint(x: 1.0, y: 0.9),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                TrendLineShape(points: points)
                    .trim(from: 0, to: drawProgress)
                    .stroke(Theme.pillFill, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                if showBadge {
                    Image(systemName: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(.orange))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: chartHeight)

            HStack {
                ForEach(xAxisLabels, id: \.self) { label in
                    Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(.secondary)
                    if label != xAxisLabels.last { Spacer() }
                }
            }
        }
        .padding(chartHeight < 160 ? 14 : 20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.systemGray6)))
        .onAppear {
            withAnimation(.easeOut(duration: 1.4)) { drawProgress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showBadge = true }
            }
        }
    }
}

/// "A simpler way to workout and improve health" -- side-by-side growing
/// bars, without vs. with Soma.
struct ComparisonBarView: View {
    @State private var grown = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            column(label: "Without Soma", height: 70, color: Color(.systemGray4), icon: "person.fill", iconIsLight: true)
            column(label: "With Soma", height: grown ? 170 : 70, color: Theme.pillFill, icon: "checkmark.circle.fill", iconIsLight: false)
        }
        .frame(height: 210, alignment: .bottom)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) {
                grown = true
            }
        }
    }

    private func column(label: LocalizedStringKey, height: CGFloat, color: Color, icon: String, iconIsLight: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconIsLight ? Color.secondary : Color.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(iconIsLight ? Color.white : color))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .frame(width: 72, height: height)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
    }
}
