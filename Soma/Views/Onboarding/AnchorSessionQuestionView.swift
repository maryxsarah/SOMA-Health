import SwiftUI

/// Optional recurring class/activity (Phase 4: see
/// docs/coaching-personalization-plan.md) -- e.g. a Tuesday hot yoga class
/// or a Saturday tennis league -- that the rest of the week gets built
/// around (generate-workout-plan's forward-looking scheduling, same
/// mechanism as a sport goal's schedule days). Always skippable, same
/// "structured tags drive logic, Continue never gated" rule as
/// BlockersNotesQuestionView. Reuses WeekdayMiniPicker (SportGoalComponents.swift)
/// unchanged -- same 0=Sun..6=Sat convention SportGoals' scheduleDays
/// already uses, so this field and a sport goal's schedule can be handled
/// identically server-side.
struct AnchorSessionQuestionView: View {
    let progress: Double
    @Binding var name: String
    @Binding var days: Set<Int>
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text("Do you have a weekly class or activity to plan around?")
                    .font(Theme.display)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Optional -- e.g. a Tuesday hot yoga class or a Saturday tennis league. We'll build the rest of your week so you're not gassed going in, or wiped out after.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 20) {
                TextField("e.g. \"Hot Yoga\", \"Tennis league\"", text: $name)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Which day(s) is it usually on?")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    WeekdayMiniPicker(selected: $days)
                }
            }
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
    AnchorSessionQuestionView(progress: 0.8, name: .constant(""), days: .constant([]), onBack: {}, onContinue: {})
}
