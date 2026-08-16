import SwiftUI

/// "We want you to try Soma for free" -- first of two soft reassurance
/// screens before the actual paywall.
struct TryFreeReassuranceStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            OrbView(state: .idle)
                .scaleEffect(0.75)
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                Text(String(localized: "onboarding.tryFreeReassurance.title", defaultValue: "We want you to try Soma for free", comment: "Headline on the try-for-free reassurance step"))
                    .font(Theme.display)
                    .multilineTextAlignment(.center)

                Label(LocalizedStringKey(String(localized: "onboarding.tryFreeReassurance.paymentBadge", defaultValue: "No Payment Due Now", comment: "Reassurance badge indicating no payment is due now")), systemImage: "checkmark.circle.fill")
                    .font(.body.bold())
                    .foregroundStyle(Theme.pillFill)
            }
            .padding(.horizontal, 28)

            Spacer()

            PillButton(title: LocalizedStringKey(String(localized: "onboarding.tryFreeReassurance.continueButton", defaultValue: "Try Now", comment: "Continue button on the try-for-free reassurance step")), action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
