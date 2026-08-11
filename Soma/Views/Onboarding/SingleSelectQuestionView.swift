import SwiftUI

/// Generic single-select survey screen: progress bar, headline, optional
/// subtext, a scrollable list of option rows, Continue gated on a
/// selection. Reused by ~7 of the onboarding questions (sex, workout
/// frequency, referral source, goal, diet type, accomplishment) so each
/// only needs to supply copy + the option type, not a bespoke screen.
struct SingleSelectQuestionView<Option: SurveyOption>: View {
    let headline: LocalizedStringKey
    var subtext: LocalizedStringKey? = nil
    let progress: Double
    /// Defaults to every case; pass an explicit curated subset (e.g.
    /// GoalTag.onboardingOptions) when a screen needs fewer/reordered
    /// options than the type's full case list.
    var options: [Option] = Array(Option.allCases)
    @Binding var selection: Option?
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
                            isSelected: selection == option,
                            style: .radio
                        ) {
                            selection = option
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            PillButton(title: "Continue", isEnabled: selection != nil, action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
