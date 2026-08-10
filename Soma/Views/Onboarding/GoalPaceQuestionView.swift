import SwiftUI

/// "How fast do you want to reach your goal?" -- three-position slider
/// with a live-updating, deterministic (not AI-generated) timeline
/// estimate. `weightDeltaKg` is only used to shape the estimate shown;
/// the actual daily recommendation logic never depends on it.
struct GoalPaceQuestionView: View {
    let progress: Double
    @Binding var pace: GoalPace
    let weightDeltaKg: Double
    /// Raw kg values (not just the delta above) so the new trajectory
    /// chart can label its Today/Goal points with real numbers -- see
    /// GoalTrajectoryChartView.
    let startWeightKg: Double?
    let goalWeightKg: Double?
    let onBack: () -> Void
    let onContinue: () -> Void

    private let paceOrder: [GoalPace] = [.slow, .recommended, .fast]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text("How fast do you want to reach your goal?")
                    .font(Theme.display)
                Text("Your speed to reach your goal.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            VStack(spacing: 20) {
                // Compact height (matches UpwardTrendChartView's own
                // "compact call sites... must fit without scrolling" rule)
                // -- this screen has no ScrollView, so the chart stays
                // small enough that the slider/card/button below it never
                // risk getting pushed off a small device's screen.
                GoalTrajectoryChartView(
                    startWeightKg: startWeightKg, goalWeightKg: goalWeightKg,
                    estimatedMonths: estimatedMonths, chartHeight: 90
                )

                HStack {
                    ForEach(paceOrder) { option in
                        VStack(spacing: 6) {
                            Image(systemName: option.systemImageName)
                                .font(.title2)
                                .foregroundStyle(pace == option ? Theme.pillFill : Color.secondary)
                            Text(option.displayName)
                                .font(.caption.bold())
                                .foregroundStyle(pace == option ? Theme.pillFill : Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Slider(
                    value: Binding(
                        get: { Double(paceOrder.firstIndex(of: pace) ?? 1) },
                        set: { pace = paceOrder[Int($0.rounded())] }
                    ),
                    in: 0...2,
                    step: 1
                )
                .tint(Theme.pillFill)

                CardView {
                    Text(estimateHeadline)
                        .font(.body.bold())
                    Text(estimateDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.25), value: pace)

            Spacer()

            PillButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }

    private var estimatedMonths: Int {
        GoalPace.estimatedMonths(deltaKg: weightDeltaKg, pace: pace)
    }

    private var estimateHeadline: String {
        "You should reach your goal in \(estimatedMonths) month\(estimatedMonths == 1 ? "" : "s")"
    }

    private var estimateDescription: String {
        switch pace {
        case .slow: "Going slow means a gentler, more sustainable daily plan."
        case .recommended: "A balanced pace that fits steady, lasting progress."
        case .fast: "A faster pace means a more demanding daily plan."
        }
    }
}
