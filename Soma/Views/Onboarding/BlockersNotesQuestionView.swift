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
                Text("Anything else in your way?")
                    .font(Theme.display)
                Text("Optional -- a sentence or two helps us understand your situation. Totally fine to skip.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            TextField("e.g. \"I travel a lot for work\"", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            Spacer()

            PillButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}

#Preview {
    BlockersNotesQuestionView(progress: 0.7, notes: .constant(""), onBack: {}, onContinue: {})
}
