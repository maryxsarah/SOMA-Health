import SwiftUI

/// The feature's one designed asset: a Soma-branded, screenshot-worthy
/// card with three text variants on a single layout (§6a note 2).
enum AchievementCardVariant {
    /// Target range hit -- accent styling, earned celebration.
    case celebratory(goalName: String, deltaText: String, dateRange: String)
    /// Honest miss or modest gain -- neutral ink, still recorded.
    case neutral(goalName: String, deltaText: String, dateRange: String)
    /// Coach export: sessions done + chart + "Built with Coach X" header.
    case coachExport(goalName: String, sessionsLine: String, coachName: String?, chartValues: [(date: String, value: Double)], dateRange: String)
}

struct AchievementCardView: View {
    let variant: AchievementCardVariant

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SOMA")
                    .font(.system(size: 12, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(accentColor)
                Spacer()
                Text(headline.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(SomaTokens.ink3)
            }

            Text(goalName)
                .font(.system(size: 22, design: .serif).italic())
                .foregroundStyle(SomaTokens.ink)

            Text(bigLine)
                .font(.system(size: 40, design: .serif).italic())
                .foregroundStyle(accentColor)

            if case .coachExport(_, _, _, let chartValues, _) = variant, chartValues.count >= 2 {
                AxisLabeledTrendChart(values: chartValues)
                    .padding(.top, 2)
            }

            HStack {
                Text(footerLeft)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink2)
                Spacer()
                if let footerRight {
                    Text(footerRight)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink3)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rCard, style: .continuous)
                .fill(SomaTokens.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: SomaTokens.rCard, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .somaCardShadow()
    }

    private var accentColor: Color {
        switch variant {
        case .celebratory: SomaTokens.accent
        case .neutral, .coachExport: SomaTokens.ink
        }
    }

    private var borderColor: Color {
        switch variant {
        case .celebratory: SomaTokens.accentSoft
        case .neutral, .coachExport: SomaTokens.hairline
        }
    }

    private var headline: String {
        switch variant {
        case .celebratory: return "Goal achieved"
        case .neutral: return "Block complete"
        case .coachExport(_, _, let coachName, _, _):
            if let coachName, !coachName.isEmpty { return "Built with Coach \(coachName)" }
            return "Coach's task"
        }
    }

    private var goalName: String {
        switch variant {
        case .celebratory(let name, _, _), .neutral(let name, _, _), .coachExport(let name, _, _, _, _): return name
        }
    }

    private var bigLine: String {
        switch variant {
        case .celebratory(_, let delta, _), .neutral(_, let delta, _): delta
        case .coachExport(_, let sessions, _, _, _): sessions
        }
    }

    private var footerLeft: String {
        switch variant {
        case .celebratory(_, _, let range), .neutral(_, _, let range), .coachExport(_, _, _, _, let range): return range
        }
    }

    private var footerRight: String? {
        switch variant {
        case .celebratory: "Goal achieved"
        case .neutral: "Block complete"
        case .coachExport: nil
        }
    }
}

/// Renders the card to a shareable image and offers it via ShareLink --
/// the iOS share sheet, no custom share UI.
struct AchievementCardShareLink: View {
    let variant: AchievementCardVariant

    @State private var rendered: UIImage?

    var body: some View {
        Group {
            if let rendered {
                ShareLink(
                    item: Image(uiImage: rendered),
                    preview: SharePreview("Soma goal card", image: Image(uiImage: rendered))
                ) {
                    shareLabel
                }
            } else {
                shareLabel.opacity(0.45)
            }
        }
        .task { render() }
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(SomaTokens.accent)
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(
            content: AchievementCardView(variant: variant)
                .frame(width: 350)
                .background(Color.white)
        )
        renderer.scale = 3
        rendered = renderer.uiImage
    }
}

#Preview {
    VStack(spacing: 16) {
        AchievementCardView(variant: .celebratory(goalName: "Vertical jump", deltaText: "+5 cm", dateRange: "Aug–Oct 2026"))
        AchievementCardView(variant: .neutral(goalName: "Vertical jump", deltaText: "+1 cm", dateRange: "Aug–Oct 2026"))
        AchievementCardView(variant: .coachExport(goalName: "Approach jump", sessionsLine: "14 of 24 sessions", coachName: "Elena", chartValues: [("2026-08-01", 41), ("2026-09-01", 43), ("2026-09-28", 45)], dateRange: "Aug–Sep 2026"))
    }
    .padding()
    .background(Color(red: 0.9, green: 0.94, blue: 1))
}
