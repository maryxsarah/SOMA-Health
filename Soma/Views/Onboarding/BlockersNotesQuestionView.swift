import SwiftUI

/// Optional free-text elaboration on the blockers multi-select just before
/// it -- same "structured tags drive logic, free text is human context
/// only" split as injuryTags/injuryNotes. Always skippable: Continue is
/// never gated on non-empty text, same as the blockers step itself.
struct BlockersNotesQuestionView: View {
    let progress: Double
    @Binding var notes: String
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "onboarding.blockersNotes.title", defaultValue: "Anything else in your way?", comment: "Headline on the blockers notes question step"))
                    .font(Theme.display)
                Text(String(localized: "onboarding.blockersNotes.subtitle", defaultValue: "Optional -- a sentence or two helps us understand your situation. Totally fine to skip.", comment: "Subtitle on the blockers notes question step"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            TextField(String(localized: "onboarding.blockersNotes.placeholder", defaultValue: "e.g. \"I travel a lot for work\"", comment: "Placeholder text for the optional blockers free-text field"), text: $notes, axis: .vertical)
                .lineLimit(4...8)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassCardFlat(cornerRadius: SomaTokens.rXL)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            Spacer()

            PillButton(title: LocalizedStringKey(String(localized: "onboarding.blockersNotes.continueButton", defaultValue: "Continue", comment: "Continue button on the blockers notes question step")), action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}

#Preview {
    BlockersNotesQuestionView(progress: 0.7, notes: .constant(""), onBack: {}, onContinue: {})
}
