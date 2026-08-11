import SwiftUI

/// "Designed to help you stay on track" -- the upward trend chart screen.
struct TrustChartStepView: View {
    let progress: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            Text("Designed to help you stay on track")
                .font(Theme.display)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            UpwardTrendChartView(xAxisLabels: ["Month 1", "Month 3", "Month 6"])
                .padding(.horizontal, 24)

            Text("Tailor your plan and stay consistent over time.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 16)

            Spacer()

            PillButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}

/// "Losing/Gaining X kg starts with a plan!" -- reacts to the delta
/// between current and desired weight picked in the two prior steps.
struct WeightDeltaReactionView: View {
    let deltaKg: Double
    let progress: Double
    let onBack: () -> Void
    let onContinue: () -> Void

    private var amountText: String { String(format: "%.1f kg", abs(deltaKg)) }

    /// Built as one localized sentence per direction (not concatenated
    /// English fragments) since word order and verb form vary by
    /// language; the amount substring is located after localization and
    /// colored, so styling survives translation and reordering.
    private var headline: AttributedString {
        let template: String
        if deltaKg < 0 {
            template = String(
                localized: "onboarding.weightDelta.headlineLosing",
                defaultValue: "Losing \(amountText) starts with a plan!",
                comment: "Onboarding reaction headline when the user's target is a weight loss; %@ is an amount like '5.0 kg'"
            )
        } else {
            template = String(
                localized: "onboarding.weightDelta.headlineGaining",
                defaultValue: "Gaining \(amountText) starts with a plan!",
                comment: "Onboarding reaction headline when the user's target is a weight gain; %@ is an amount like '5.0 kg'"
            )
        }
        var attributed = AttributedString(template)
        if let range = attributed.range(of: amountText) {
            attributed[range].foregroundColor = .orange
        }
        return attributed
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            Spacer()

            VStack(spacing: 14) {
                Text(headline)
                    .font(Theme.display)
                    .multilineTextAlignment(.center)

                Text("We help you understand your body better and make steady progress with tailored daily plans based on your habits, goals, health information, and timeline.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            Spacer()

            PillButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}

/// "A simpler way to workout and improve health" -- was a static "Without
/// Soma / With Soma" bar illustration with no real data behind it at all
/// (fixed heights, same for every user); now the same real trajectory
/// chart as the other survey chart screens, reinforcing the actual plan
/// rather than a generic comparison prop.
struct ComparisonStepView: View {
    let progress: Double
    let weightDeltaKg: Double
    let pace: GoalPace
    let startWeightKg: Double?
    let goalWeightKg: Double?
    let onBack: () -> Void
    let onContinue: () -> Void

    private var estimatedMonths: Int {
        GoalPace.estimatedMonths(deltaKg: weightDeltaKg, pace: pace)
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text("A simpler way to workout and improve health")
                    .font(Theme.display)
                Text("Get your daily plan in seconds, tailored to your health. Follow your plan, and see your progress add up.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            GoalTrajectoryChartView(
                startWeightKg: startWeightKg, goalWeightKg: goalWeightKg,
                estimatedMonths: estimatedMonths, chartHeight: 160
            )
            .padding(.horizontal, 24)

            Spacer()

            PillButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}

/// "Here's your realistic timeline" -- upward trend screen, now driven by
/// the real weight-delta + pace the user picked two screens ago (was a
/// generic "you're right on track" claim before anything had happened,
/// with a hardcoded 3/7/30-day chart unrelated to their actual answer --
/// tester feedback: "needs to be realistic with recommended timeline").
struct OnTrackStepView: View {
    let progress: Double
    let weightDeltaKg: Double
    let pace: GoalPace
    let startWeightKg: Double?
    let goalWeightKg: Double?
    /// By this point in the survey (see SurveyStep's order in
    /// OnboardingSurveyView) goal/journeyStage/blockers/dietType have all
    /// already been answered -- the last chart screen where a real,
    /// non-thin "Highlights of your plan" list is honest to show.
    let goalTags: Set<GoalTag>
    let journeyStage: JourneyStage?
    let blockers: Set<BlockerTag>
    let dietType: DietType?
    let onBack: () -> Void
    let onContinue: () -> Void

    private var estimatedMonths: Int {
        GoalPace.estimatedMonths(deltaKg: weightDeltaKg, pace: pace)
    }

    private var monthLabel: String {
        String(
            localized: "onboarding.monthsStandalone",
            defaultValue: "\(estimatedMonths) months",
            comment: "Bare month count used as a chart axis label and inline in a sentence, pluralized by count"
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: progress, onBack: onBack)

            Text("Your tailored health journey")
                .font(Theme.eyebrow)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)

            Text("Here's your realistic timeline")
                .font(Theme.display)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            GoalTrajectoryChartView(
                startWeightKg: startWeightKg, goalWeightKg: goalWeightKg,
                estimatedMonths: estimatedMonths, chartHeight: 130
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Text("At a \(pace.displayName.lowercased()) pace, most people following their plan consistently reach a goal like this in about \(monthLabel). Consistency in the early weeks matters most.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 16)

            // Capped to 3 (not the full 4) -- this screen has no
            // ScrollView, unlike PlanSummaryStepView's own use of this
            // same list, so a 4th line risks pushing Continue off a small
            // device's screen.
            PlanHighlightsListView(items: PlanHighlightsListView.build(
                goalTags: goalTags, journeyStage: journeyStage,
                blockers: blockers, dietType: dietType, maxItems: 3
            ))
            .padding(.horizontal, 32)
            .padding(.top, 14)

            Spacer()

            PillButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}

/// "Thank you for trusting us!" -- celebratory screen closing out the
/// survey portion, before Connect Device.
struct CelebrationStepView: View {
    let onContinue: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.orbSecondary.opacity(0.35), Theme.orbPrimary.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 110
                        )
                    )
                    .frame(width: 220, height: 220)
                    .blur(radius: 8)
                    .scaleEffect(pulse ? 1.05 : 0.95)

                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.pillFill)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            VStack(spacing: 8) {
                Text("Thank you for trusting us!")
                    .font(Theme.display)
                Text("Now let's create your first tailored plan for today.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

            CardView {
                Text("Tailored to your Health Goals")
                    .font(.body.bold())
                Text("We'll use your answers and device connection to tailor your plan, goals, and recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            Spacer()

            PillButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
    }
}
