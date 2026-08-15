import SwiftUI

/// Generic Yes/No survey screen (personal trainer question, etc.).
struct BinaryYesNoQuestionView: View {
    let headline: LocalizedStringKey
    var subtext: LocalizedStringKey? = nil
    let progress: Double
    let onBack: () -> Void
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            Spacer()

            VStack(spacing: 10) {
                Text(headline)
                    .font(Theme.display)
                    .multilineTextAlignment(.center)
                if let subtext {
                    Text(subtext)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 10) {
                PillButton(title: "Yes") { onAnswer(true) }
                Button {
                    onAnswer(false)
                } label: {
                    Text("No")
                        .font(.body.bold())
                        .foregroundStyle(SomaTokens.inkParagraph)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .glassCardFlat(cornerRadius: SomaTokens.rPill)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
