import SwiftUI

/// Reused for both "What's your weight?" and "What's your desired
/// weight?" -- only the headline/subtext and starting value differ.
struct WeightQuestionView: View {
    let headline: String
    var subtext: String? = nil
    let progress: Double
    @Binding var weightKg: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(Theme.display)
                if let subtext {
                    Text(subtext)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            WeightScalePicker(weightKg: $weightKg)

            Spacer()

            PillButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
