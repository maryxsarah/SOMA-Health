import SwiftUI

/// "We'll send you a reminder before your trial ends" -- second soft
/// reassurance screen, directly before the paywall.
struct TrialReminderStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(.systemGray3))
                Text("1")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.red))
                    .offset(x: 6, y: -4)
            }

            VStack(spacing: 10) {
                Text("We'll send you a reminder before your trial ends")
                    .font(Theme.display)
                    .multilineTextAlignment(.center)
                Text("As long as notifications are enabled.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Label("No Payment Due Today", systemImage: "checkmark.circle.fill")
                    .font(.body.bold())
                    .foregroundStyle(Theme.pillFill)
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)

            Spacer()

            PillButton(title: "Continue for FREE", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
