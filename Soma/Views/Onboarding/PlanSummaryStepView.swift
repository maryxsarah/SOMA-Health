import SwiftUI

/// Summary of the user's goal, connected devices, and first daily
/// recommendation -- the payoff moment right after the loading sequence.
struct PlanSummaryStepView: View {
    @EnvironmentObject private var appState: AppState
    let onContinue: () -> Void

    /// Same real values OnboardingSurveyView.finish() stashed via
    /// UserDefaults right after the survey submitted -- see its own doc
    /// comment for why this screen has no other way to reach them
    /// (constructed later, in PostSetupFlowView, with no direct binding
    /// to the survey's in-memory `answers`).
    private var startWeightKg: Double? {
        let value = UserDefaults.standard.double(forKey: OnboardingSurveyView.startWeightKgKey)
        return value > 0 ? value : nil
    }

    private var goalWeightKg: Double? {
        let value = UserDefaults.standard.double(forKey: OnboardingSurveyView.goalWeightKgKey)
        return value > 0 ? value : nil
    }

    /// Falls back to recomputing the same deterministic estimate from the
    /// stashed weight/pace if the months figure itself is somehow missing
    /// -- still a real, derived number, never a fabricated one.
    private var estimatedMonths: Int? {
        let stored = UserDefaults.standard.integer(forKey: OnboardingSurveyView.estimatedGoalMonthsKey)
        if stored > 0 { return stored }
        guard let startWeightKg, let goalWeightKg else { return nil }
        let pace = UserDefaults.standard.string(forKey: OnboardingSurveyView.goalPaceKey).flatMap(GoalPace.init(rawValue:)) ?? .recommended
        return GoalPace.estimatedMonths(deltaKg: goalWeightKg - startWeightKg, pace: pace)
    }

    private var goalTags: Set<GoalTag> {
        Set((UserDefaults.standard.stringArray(forKey: OnboardingSurveyView.goalTagsKey) ?? []).compactMap(GoalTag.init(rawValue:)))
    }

    private var journeyStage: JourneyStage? {
        UserDefaults.standard.string(forKey: OnboardingSurveyView.journeyStageKey).flatMap(JourneyStage.init(rawValue:))
    }

    private var blockers: Set<BlockerTag> {
        Set((UserDefaults.standard.stringArray(forKey: OnboardingSurveyView.blockersKey) ?? []).compactMap(BlockerTag.init(rawValue:)))
    }

    private var dietType: DietType? {
        UserDefaults.standard.string(forKey: OnboardingSurveyView.dietTypeKey).flatMap(DietType.init(rawValue:))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.pillFill)
                    .padding(.top, 12)

                Text("Your plan is ready")
                    .font(Theme.display)

                CardView {
                    Text("Estimated progress")
                        .font(.body.bold())
                    GoalTrajectoryChartView(
                        startWeightKg: startWeightKg, goalWeightKg: goalWeightKg,
                        estimatedMonths: estimatedMonths ?? 1, chartHeight: 130
                    )
                    // Full 4 lines here (unlike OnTrackStepView's 3) --
                    // this screen already scrolls, and by now every
                    // source field (goal/journeyStage/blockers/dietType)
                    // has actually been collected.
                    PlanHighlightsListView(items: PlanHighlightsListView.build(
                        goalTags: goalTags, journeyStage: journeyStage,
                        blockers: blockers, dietType: dietType, maxItems: 4
                    ))
                }

                CardView {
                    Text("Connected devices")
                        .font(.body.bold())
                    if appState.connectedProviders.isEmpty {
                        Text("None yet -- you can connect anytime from Profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(appState.connectedProviders)) { provider in
                            Label(provider.displayName, systemImage: provider.systemImageName)
                                .font(.subheadline)
                        }
                    }
                }

                CardView {
                    Text("Your daily recommendation")
                        .font(.body.bold())
                    if let recommendation = appState.currentRecommendation {
                        Text(recommendation.category.displayTitle)
                            .font(Theme.display)
                        Text(recommendation.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Your first recommendation will be ready shortly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                PillButton(title: "Let's get started!", action: onContinue)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
        .somaBackground()
    }
}
