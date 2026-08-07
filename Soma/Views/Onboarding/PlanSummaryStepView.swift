import SwiftUI

/// Summary of the user's goal, connected devices, and first daily
/// recommendation -- the payoff moment right after the loading sequence.
struct PlanSummaryStepView: View {
    @EnvironmentObject private var appState: AppState
    let onContinue: () -> Void

    /// Same real number OnTrackStepView showed earlier in the survey
    /// (stashed via UserDefaults at that point) -- falls back to a plain
    /// "Now"/"Ahead" pair if it's somehow missing rather than a fabricated
    /// "1 Month/3 Months" guess.
    private var estimatedMonths: Int? {
        let stored = UserDefaults.standard.integer(forKey: OnboardingSurveyView.estimatedGoalMonthsKey)
        return stored > 0 ? stored : nil
    }

    private var chartLabels: [String] {
        guard let estimatedMonths else { return ["Now", "Ahead"] }
        return ["Now", "Halfway", "\(estimatedMonths) month\(estimatedMonths == 1 ? "" : "s")"]
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
                    UpwardTrendChartView(xAxisLabels: chartLabels, chartHeight: 110)
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
