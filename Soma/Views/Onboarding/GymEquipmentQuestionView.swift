import SwiftUI

/// "What's in your gym?" -- feeds generate-workout-plan (available
/// exercises are filtered to the gear the user actually has). Same
/// chrome as KitchenEquipmentQuestionView (OnboardingTopBar, PillButton,
/// never gates Continue -- an empty answer here is real and valid, same
/// reasoning as that screen), body is the shared GymEquipmentPicker
/// rather than a fixed row list, since this catalog (78 items) is far
/// too long for that shape.
struct GymEquipmentQuestionView: View {
    let progress: Double
    @Binding var selection: Set<GymEquipmentTag>
    @Binding var customItems: [String]
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "gymEquipmentQuestion.title", defaultValue: "What's in your gym?", comment: "Onboarding gym-equipment question screen title"))
                    .font(Theme.display)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "gymEquipmentQuestion.subtitle", defaultValue: "So we only ever build workouts around gear you actually have. Optional -- skip if you're not sure yet.", comment: "Onboarding gym-equipment question screen subtitle/explainer"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView {
                GymEquipmentPicker(selection: $selection, customItems: $customItems)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .dismissKeyboardOnTap()
            }
            .scrollDismissesKeyboard(.interactively)

            PillButton(title: "Continue", action: {
                // Same reasoning as KitchenEquipmentQuestionView: this
                // step's own free-text "add other" field can leave the
                // keyboard up, and Continue is a confirm action, not just
                // a tap elsewhere.
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
                onContinue()
            })
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}

#Preview {
    GymEquipmentQuestionView(progress: 0.75, selection: .constant([]), customItems: .constant([]), onBack: {}, onContinue: {})
}
