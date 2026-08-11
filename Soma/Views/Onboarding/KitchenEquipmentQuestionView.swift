import SwiftUI

/// "What's in your kitchen?" -- feeds generate-meal-recommendation (a
/// suggested recipe must never call for equipment outside this set). Same
/// chrome as MultiSelectQuestionView (OnboardingTopBar, checkbox
/// SurveyOptionRow list, PillButton), but bespoke rather than an instance
/// of that generic component for two reasons:
///   1. Continue is never gated on a selection -- unlike every other
///      multi-select step, an empty answer here is a real, valid choice
///      ("What can I make?"'s own first-use prompt is where a skip
///      actually gets asked about, with a sane stove+oven+microwave
///      default; this step forcing a choice would just be onboarding
///      friction for a feature the user hasn't reached yet).
///   2. The "Other" chip reveals an inline free-text field for
///      comma-separated custom items, which MultiSelectQuestionView's
///      fixed row-list shape has no room for.
struct KitchenEquipmentQuestionView: View {
    let progress: Double
    @Binding var selection: Set<KitchenEquipmentTag>
    @Binding var otherText: String
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text("What's in your kitchen?")
                    .font(Theme.display)
                    .fixedSize(horizontal: false, vertical: true)
                Text("So we only ever suggest recipes you can actually cook. Optional -- skip if you're not sure yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(KitchenEquipmentTag.allCases) { tag in
                        SurveyOptionRow(
                            title: tag.displayName,
                            systemImageName: tag.systemImageName,
                            isSelected: selection.contains(tag),
                            style: .checkbox
                        ) {
                            if selection.contains(tag) {
                                selection.remove(tag)
                            } else {
                                selection.insert(tag)
                            }
                        }
                    }
                    if selection.contains(.other) {
                        TextField("What else? (comma-separated)", text: $otherText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .dismissKeyboardOnTap()
            }
            .scrollDismissesKeyboard(.interactively)

            PillButton(title: "Continue", action: {
                // The "Other" field's keyboard would otherwise still be
                // up when this step transitions to the next question --
                // Continue is a confirm action, not just a tap elsewhere,
                // so dismissKeyboardOnTap() alone (only fires on the
                // ScrollView itself) doesn't cover it.
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
    KitchenEquipmentQuestionView(progress: 0.7, selection: .constant([]), otherText: .constant(""), onBack: {}, onContinue: {})
}
