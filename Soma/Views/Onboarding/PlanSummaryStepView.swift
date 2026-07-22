import SwiftUI

/// Summary of the user's goal, connected devices, and first daily
/// recommendation -- the payoff moment right after the loading sequence.
struct PlanSummaryStepView: View {
    @EnvironmentObject private var appState: AppState
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.pillFill)
                    .padding(.top, 24)

                Text("Your plan is ready")
                    .font(Theme.display)

                CardView {
                    Text("Estimated progress")
                        .font(.body.bold())
                    UpwardTrendChartView(xAxisLabels: ["Now", "1 Month", "3 Months"])
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
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Your first recommendation will be ready shortly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                PillButton(title: "Let's get started!", action: onContinue)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .somaBackground()
    }
}
