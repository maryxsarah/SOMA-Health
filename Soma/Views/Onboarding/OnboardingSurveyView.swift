import SwiftUI

private enum SurveyStep: Int, CaseIterable {
    case sex, workoutFrequency, dateOfBirth, referralSource, trustChart
    case currentWeight, personalTrainer, goal, desiredWeight, weightDeltaReaction
    case goalPace, comparisonBar, blockers, dietType, accomplishment
    case onTrack, celebration
}

/// Runs the whole survey sequence (screens 2-16b of the spec: sex through
/// the post-trust "thank you" celebration) between Sign in with Apple and
/// Connect Device. Holds every answer locally and writes it all to
/// Supabase in one batch at the end, rather than a network call per step.
struct OnboardingSurveyView: View {
    @EnvironmentObject private var appState: AppState

    @State private var step: SurveyStep = .sex
    @State private var answers = OnboardingSurveyAnswers()

    var body: some View {
        Group {
            switch step {
            case .sex:
                SingleSelectQuestionView(
                    headline: "Choose your sex",
                    subtext: "This helps us personalize your experience.",
                    progress: progress,
                    selection: $answers.sex,
                    onBack: goBack,
                    onContinue: advance
                )
            case .workoutFrequency:
                SingleSelectQuestionView(
                    headline: "How many workouts do you do per week?",
                    subtext: "This helps Soma calibrate your tailored plan.",
                    progress: progress,
                    selection: $answers.workoutFrequency,
                    onBack: goBack,
                    onContinue: advance
                )
            case .dateOfBirth:
                DateOfBirthQuestionView(
                    progress: progress,
                    dateOfBirth: Binding(
                        get: { answers.dateOfBirth ?? Self.defaultDateOfBirth },
                        set: { answers.dateOfBirth = $0 }
                    ),
                    onBack: goBack,
                    onContinue: advance
                )
            case .referralSource:
                SingleSelectQuestionView(
                    headline: "Where did you hear about us?",
                    progress: progress,
                    selection: $answers.referralSource,
                    onBack: goBack,
                    onContinue: advance
                )
            case .trustChart:
                TrustChartStepView(progress: progress, onBack: goBack, onContinue: advance)
            case .currentWeight:
                WeightQuestionView(
                    headline: "What's your weight?",
                    progress: progress,
                    weightKg: Binding(
                        get: { answers.weightKg ?? 70 },
                        set: { answers.weightKg = $0 }
                    ),
                    onBack: goBack,
                    onContinue: advance
                )
            case .personalTrainer:
                BinaryYesNoQuestionView(
                    headline: "Do you currently work with a personal trainer?",
                    progress: progress,
                    onBack: goBack,
                    onAnswer: { answers.worksWithTrainer = $0; advance() }
                )
            case .goal:
                MultiSelectQuestionView(
                    headline: "What is your goal?",
                    progress: progress,
                    options: GoalTag.onboardingOptions,
                    selection: $answers.goal,
                    onBack: goBack,
                    onContinue: advance
                )
            case .desiredWeight:
                WeightQuestionView(
                    headline: "What's your desired weight?",
                    progress: progress,
                    weightKg: Binding(
                        get: { answers.desiredWeightKg ?? (answers.weightKg ?? 70) },
                        set: { answers.desiredWeightKg = $0 }
                    ),
                    onBack: goBack,
                    onContinue: advance
                )
            case .weightDeltaReaction:
                WeightDeltaReactionView(deltaKg: weightDelta, progress: progress, onBack: goBack, onContinue: advance)
            case .goalPace:
                GoalPaceQuestionView(
                    progress: progress,
                    pace: Binding(
                        get: { answers.goalPace ?? .recommended },
                        set: { answers.goalPace = $0 }
                    ),
                    weightDeltaKg: weightDelta,
                    onBack: goBack,
                    onContinue: advance
                )
            case .comparisonBar:
                ComparisonStepView(progress: progress, onBack: goBack, onContinue: advance)
            case .blockers:
                MultiSelectQuestionView(
                    headline: "What's blocking you from your current goal?",
                    progress: progress,
                    selection: $answers.blockers,
                    onBack: goBack,
                    onContinue: advance
                )
            case .dietType:
                SingleSelectQuestionView(
                    headline: "Do you follow a specific diet?",
                    progress: progress,
                    selection: $answers.dietType,
                    onBack: goBack,
                    onContinue: advance
                )
            case .accomplishment:
                MultiSelectQuestionView(
                    headline: "What would you like to accomplish?",
                    progress: progress,
                    selection: $answers.accomplishmentGoals,
                    onBack: goBack,
                    onContinue: advance
                )
            case .onTrack:
                OnTrackStepView(
                    progress: progress,
                    weightDeltaKg: weightDelta,
                    pace: answers.goalPace ?? .recommended,
                    onBack: goBack,
                    onContinue: advance
                )
            case .celebration:
                CelebrationStepView(onContinue: finish)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private var progress: Double {
        Double(step.rawValue + 1) / Double(SurveyStep.allCases.count)
    }

    private var weightDelta: Double {
        (answers.desiredWeightKg ?? answers.weightKg ?? 0) - (answers.weightKg ?? 0)
    }

    private func advance() {
        if let next = SurveyStep(rawValue: step.rawValue + 1) {
            step = next
        } else {
            finish()
        }
    }

    private func goBack() {
        if let previous = SurveyStep(rawValue: step.rawValue - 1) {
            step = previous
        }
    }

    private func finish() {
        // Stashed locally (not just sent to the server) so PlanSummaryStepView,
        // several screens later in PostSetupFlowView, can show the same real
        // timeline without a round-trip fetch -- same one-off UserDefaults
        // pattern AppState itself uses for onboarding-scoped values.
        UserDefaults.standard.set(
            GoalPace.estimatedMonths(deltaKg: weightDelta, pace: answers.goalPace ?? .recommended),
            forKey: Self.estimatedGoalMonthsKey
        )
        Task {
            guard let userId = SupabaseClient.shared.currentUserID else { return }
            try? await SupabaseClient.shared.saveOnboardingSurvey(id: userId, answers: answers)
        }
        appState.screen = .connectDevice
    }

    static let estimatedGoalMonthsKey = "com.soma.app.estimatedGoalMonths"

    private static var defaultDateOfBirth: Date {
        Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    }
}

#Preview {
    OnboardingSurveyView()
        .environmentObject(AppState())
}
