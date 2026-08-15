import SwiftUI

/// "We'll send you a reminder before your trial ends" -- second soft
/// reassurance screen, directly before the paywall.
struct TrialReminderStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 36))
                    .foregroundStyle(SomaTokens.accent)
                    .frame(width: 86, height: 86)
                    .glassLens(cornerRadius: 43)
                Text("1")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .glassGel(.blue, cornerRadius: 13)
                    .offset(x: 8, y: -6)
            }

            VStack(spacing: 10) {
                Text("We'll send you a reminder before your trial ends")
                    .font(Theme.display)
                    .multilineTextAlignment(.center)
                Text("As long as notifications are enabled.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .glassGel(.blue, cornerRadius: 10)
                    Text("No payment due today")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.pillFill)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: SomaTokens.rPill)
                .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)

            Spacer()

            PillButton(title: "Continue for free", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
