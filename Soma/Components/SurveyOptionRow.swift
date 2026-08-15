import SwiftUI

enum SurveyOptionRowStyle {
    case radio
    case checkbox
}

/// One selectable row: icon, title (+ optional subtitle), and a
/// radio/checkbox indicator. Used by every onboarding survey question
/// screen for consistency.
struct SurveyOptionRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImageName: String
    let isSelected: Bool
    var style: SurveyOptionRowStyle = .radio
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImageName)
                    .font(.system(size: 16))
                    .foregroundStyle(SomaTokens.accent)
                    .frame(width: 34, height: 34)
                    .glassLens(cornerRadius: 17)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.bold())
                        .foregroundStyle(isSelected ? SomaTokens.accent : SomaTokens.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(SomaTokens.ink3)
                    }
                }

                Spacer()

                indicator
            }
            .padding(15)
            .glassCardFlat()
            .overlay(
                RoundedRectangle(cornerRadius: SomaTokens.rRow, style: .continuous)
                    .strokeBorder(SomaTokens.accent.opacity(isSelected ? 0.35 : 0), lineWidth: 1.5)
            )
            .shadow(color: SomaTokens.accent.opacity(isSelected ? 0.12 : 0), radius: 8, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var indicator: some View {
        switch style {
        case .radio:
            radioIndicator
        case .checkbox:
            RoundedRectangle(cornerRadius: SomaTokens.rCheck, style: .continuous)
                .strokeBorder(isSelected ? SomaTokens.accent : SomaTokens.inkPlaceholder, lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: SomaTokens.rCheck, style: .continuous).fill(isSelected ? SomaTokens.accent : .clear))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .opacity(isSelected ? 1 : 0)
                )
        }
    }

    /// Unselected: a thin empty accent ring, no fill. Selected: the same
    /// filled-gel-disc-plus-check treatment as `WeekdayMiniPicker`'s
    /// selected day, for one consistent "this is chosen" language app-wide.
    @ViewBuilder
    private var radioIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .glassGel(.blue, cornerRadius: 11)
        } else {
            Circle()
                .strokeBorder(SomaTokens.accent.opacity(0.35), lineWidth: 1.5)
                .frame(width: 22, height: 22)
        }
    }
}
