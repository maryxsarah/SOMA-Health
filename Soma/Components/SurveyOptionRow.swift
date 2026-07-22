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
            HStack(spacing: 14) {
                Image(systemName: systemImageName)
                    .font(.body)
                    .foregroundStyle(Theme.pillFill)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.systemGray6)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                indicator
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Theme.pillFill : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var indicator: some View {
        switch style {
        case .radio:
            Circle()
                .strokeBorder(isSelected ? Theme.pillFill : Color(.systemGray4), lineWidth: 2)
                .background(Circle().fill(isSelected ? Theme.pillFill : .clear))
                .frame(width: 22, height: 22)
        case .checkbox:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSelected ? Theme.pillFill : Color(.systemGray4), lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? Theme.pillFill : .clear))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .opacity(isSelected ? 1 : 0)
                )
        }
    }
}
