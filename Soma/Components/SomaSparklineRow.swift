import SwiftUI

/// Dashboard metric row (guide 08/10): label + value in a fixed left
/// column, a flexible 30pt sparkline in accent-deep, and a right-aligned
/// delta -- colored only when the direction is good, grey otherwise.
struct SomaSparklineRow: View {
    let label: String
    let valueText: String
    /// Chronological series; fewer than 2 points renders no line (honest
    /// blank, not a fabricated flat line).
    let series: [Double]
    var deltaText: String?
    var deltaIsGood = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(SomaTokens.ink3)
                Text(valueText)
                    .font(.system(size: 14.5, weight: .semibold))
            }
            .frame(width: 96, alignment: .leading)

            if series.count > 1 {
                SparklineShape(values: series)
                    .stroke(SomaTokens.accentDeep, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }

            if let deltaText {
                Text(deltaText)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(deltaIsGood ? SomaTokens.success : SomaTokens.ink4)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct SparklineShape: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let min = values.min(), let max = values.max() else { return path }
        let range = Swift.max(max - min, 0.001)
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: rect.width * CGFloat(index) / CGFloat(values.count - 1),
                y: rect.height * (1 - CGFloat((value - min) / range))
            )
        }
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

#Preview {
    VStack(spacing: 0) {
        SomaSparklineRow(label: "Sleep", valueText: "8.5 h", series: [6.8, 7.2, 7.0, 8.1, 7.4, 8.5], deltaText: "↑ 13%", deltaIsGood: true)
        Divider()
        SomaSparklineRow(label: "HRV", valueText: "45 ms", series: [44, 46, 43, 45, 45], deltaText: "steady")
    }
    .padding()
}
