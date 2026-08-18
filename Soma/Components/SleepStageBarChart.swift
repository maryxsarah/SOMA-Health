import SwiftUI

/// Stacked Awake/REM/Light/Deep bar per day -- the one Oura-reference-design
/// tile that's genuinely buildable without fabrication (see
/// HealthMetricFamily's doc comment for why every other omitted tile has no
/// real source at all). Only shown for entries that report at least one
/// stage; a day with none is simply absent from `entries`, not a zero-height
/// bar pretending to be real data.
struct SleepStageBarChart: View {
    struct Entry {
        let date: String
        let light: Double?
        let deep: Double?
        let rem: Double?
        let awake: Double?
    }

    let entries: [Entry]

    /// Reuses 3 of this app's existing accent hues (Awake via opacity,
    /// since there are only 3 named accent colors in Theme for 4 segments)
    /// -- worth a design pass on visual distinctness, not blocking.
    private static let deepColor = Theme.pillFill
    private static let remColor = Theme.orbPrimary
    private static let lightColor = Theme.orbSecondary
    private static let awakeColor = Theme.pillFill.opacity(0.25)

    private var maxTotal: Double {
        entries.map { ($0.light ?? 0) + ($0.deep ?? 0) + ($0.rem ?? 0) + ($0.awake ?? 0) }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(entries, id: \.date) { entry in
                    VStack(spacing: 4) {
                        GeometryReader { geometry in
                            VStack(spacing: 1) {
                                Spacer(minLength: 0)
                                segment(entry.awake, color: Self.awakeColor, height: geometry.size.height)
                                segment(entry.rem, color: Self.remColor, height: geometry.size.height)
                                segment(entry.light, color: Self.lightColor, height: geometry.size.height)
                                segment(entry.deep, color: Self.deepColor, height: geometry.size.height)
                            }
                        }
                        Text(Self.shortDate(entry.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)

            HStack(spacing: 14) {
                legendItem("Deep", color: Self.deepColor)
                legendItem("REM", color: Self.remColor)
                legendItem("Light", color: Self.lightColor)
                legendItem("Awake", color: Self.awakeColor)
            }
        }
    }

    @ViewBuilder
    private func segment(_ hours: Double?, color: Color, height: CGFloat) -> some View {
        if let hours, hours > 0 {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(height: max(2, height * (hours / maxTotal)))
        }
    }

    private func legendItem(_ label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
    SleepStageBarChart(entries: [
        .init(date: "2026-07-28", light: 3.5, deep: 1.2, rem: 1.8, awake: 0.3),
        .init(date: "2026-07-29", light: 4.0, deep: 0.9, rem: 1.5, awake: 0.5),
        .init(date: "2026-07-30", light: 3.2, deep: 1.5, rem: 2.0, awake: 0.2),
    ])
    .padding()
    .somaBackground()
}
