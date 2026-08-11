import SwiftUI

/// Generic multi-select survey screen (checkboxes instead of radios) --
/// used for "what's blocking you" where more than one can apply.
struct MultiSelectQuestionView<Option: SurveyOption>: View {
    let headline: LocalizedStringKey
    var subtext: LocalizedStringKey? = nil
    let progress: Double
    var options: [Option] = Array(Option.allCases)
    @Binding var selection: Set<Option>
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(Theme.display)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtext {
                    Text(subtext)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(options) { option in
                        SurveyOptionRow(
                            title: option.displayName,
                            subtitle: option.subtitle,
                            systemImageName: option.systemImageName,
                            isSelected: selection.contains(option),
                            style: .checkbox
                        ) {
                            if selection.contains(option) {
                                selection.remove(option)
                            } else {
                                selection.insert(option)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            PillButton(title: "Continue", isEnabled: !selection.isEmpty, action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
