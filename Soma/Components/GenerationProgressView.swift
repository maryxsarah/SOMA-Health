import SwiftUI

/// Loading indicator for AI generation (gym-photo analysis/workout build,
/// AI workout plan). No server-side progress signal exists for any of
/// these single-request/response calls, so this is a smoothed, simulated
/// ramp -- not a literal completion percentage -- same honest-estimate
/// pattern most apps use for LLM-backed generation.
///
/// Advances through named stages rather than one continuous tween to a
/// static number -- a single easeOut to "90%" that then sits silent for
/// several seconds reads as stuck, even though it's working exactly as
/// designed. Rotating stage text keeps showing real activity for however
/// long the actual request takes, including past the estimate; the last
/// stage holds at 90% (never claims 100% on its own) until the caller
/// removes this view once the real response arrives.
struct GenerationProgressView: View {
    /// Stage text, in order -- each call site describes what's actually
    /// happening in its own flow (gym-photo's vision pass vs. the AI
    /// workout planner's data-driven build are different work).
    let stages: [String]
    /// Total time the ramp through all stages up to 90% takes -- tune per
    /// call site to roughly match that flow's typical latency (gym-photo's
    /// two-model vision pass runs longer than a simple text generation).
    /// If the real response hasn't arrived by the time the last stage is
    /// reached, that stage's text and 90% just hold -- still visibly
    /// "working," not frozen on a number with no context.
    var estimatedSeconds: Double = 6

    /// Default stage list for the AI-generated-workout flow. Other flows
    /// (e.g. gym-photo) pass their own via the `stages:` initializer.
    static let workoutPlanStages = [
        String(localized: "generationProgress.workoutPlanStages.stage1", defaultValue: "Reading your health data…", comment: "Loading stage while Soma reads the user's health data to build an AI workout plan"),
        String(localized: "generationProgress.workoutPlanStages.stage2", defaultValue: "Matching exercises…", comment: "Loading stage while Soma matches exercises to the user's profile and equipment for an AI workout plan"),
        String(localized: "generationProgress.workoutPlanStages.stage3", defaultValue: "Sequencing your workout…", comment: "Loading stage while Soma orders/sequences the exercises into the AI workout plan"),
        String(localized: "generationProgress.workoutPlanStages.stage4", defaultValue: "Finishing touches…", comment: "Final loading stage while Soma finishes building the AI workout plan"),
    ]

    init(stages: [String] = GenerationProgressView.workoutPlanStages, estimatedSeconds: Double = 6) {
        self.stages = stages
        self.estimatedSeconds = estimatedSeconds
    }

    @State private var progress: Double = 0
    @State private var stageIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 13b: a 5pt capsule bar -- soft accent track, light-to-deep
            // accent gradient fill -- not the system ProgressView.
            GeometryReader { geo in
                Capsule()
                    .fill(SomaTokens.accent.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0x4A / 255, green: 0x75 / 255, blue: 0xF2 / 255),
                                        SomaTokens.accent
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress)
                    }
            }
            .frame(height: 5)
            .accessibilityElement()
            .accessibilityLabel(stages[stageIndex])
            .accessibilityValue("\(Int(progress * 100))%")
            HStack {
                Text(stages[stageIndex])
                    .contentTransition(.opacity)
                    .id(stageIndex)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(SomaTokens.ink3)
        }
        .onAppear { advance() }
    }

    /// Steps through each stage on its own slice of `estimatedSeconds`,
    /// ramping to 90% by the last one, rather than one smooth tween -- the
    /// changing text is what actually reads as progress, not the bar's
    /// motion alone.
    private func advance() {
        let stepDuration = estimatedSeconds / Double(stages.count)
        let target = 0.9 * Double(stageIndex + 1) / Double(stages.count)
        withAnimation(.easeInOut(duration: stepDuration)) {
            progress = target
        }
        guard stageIndex < stages.count - 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration) {
            stageIndex += 1
            advance()
        }
    }
}

#Preview {
    GenerationProgressView()
        .padding()
        .somaBackground()
}
