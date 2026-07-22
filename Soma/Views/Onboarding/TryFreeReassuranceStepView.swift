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
                Text("We want you to try Soma for free")
                    .font(Theme.display)
                    .multilineTextAlignment(.center)

                Label("No Payment Due Now", systemImage: "checkmark.circle.fill")
                    .font(.body.bold())
                    .foregroundStyle(Theme.pillFill)
            }
            .padding(.horizontal, 28)

            Spacer()

            PillButton(title: "Try Now", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
