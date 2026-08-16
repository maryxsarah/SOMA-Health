import SwiftUI

/// Same structure as WeightQuestionView, height in cm via RulerNumberPicker
/// (the same drag-a-ruler idiom WeightScalePicker uses for weight, already
/// generalized to any unit -- see RulerNumberPicker's own header comment).
struct HeightQuestionView: View {
    let progress: Double
    @Binding var heightCm: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "onboarding.height.title", defaultValue: "What's your height?", comment: "Headline on the height question step"))
                    .font(Theme.display)
                Text(String(localized: "onboarding.height.subtitle", defaultValue: "Used to personalize your training and nutrition targets.", comment: "Subtitle on the height question step"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            RulerNumberPicker(value: $heightCm, range: 120...220, unit: SportGoalFormat.localizedUnit("cm"), step: 1)

            Spacer()

            PillButton(title: LocalizedStringKey(String(localized: "onboarding.height.continueButton", defaultValue: "Continue", comment: "Continue button on the height question step")), action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}

#Preview {
    HeightQuestionView(progress: 0.5, heightCm: .constant(170), onBack: {}, onContinue: {})
}
