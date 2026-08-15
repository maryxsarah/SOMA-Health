import SwiftUI

/// "Setting everything up for you" (10g) -- a glass-lens circular progress
/// ring with the percent inside, ONE status line that swaps in place, and
/// a checklist that gel-checks off as progress advances. This is a
/// fixed-duration perceived-personalization animation; the real
/// generate-recommendation call happens once, in parallel, via `onAppear`.
struct GeneratingPlanStepView: View {
    @EnvironmentObject private var appState: AppState
    let onFinished: () -> Void

    @State private var percent = 0
    @State private var checkedCount = 0
    @State private var statusIndex = 0
    @State private var didStartWork = false

    private let statusMessages = [
        String(localized: "Customizing your health plan..."),
        String(localized: "Analyzing your recovery data..."),
        String(localized: "Tailoring today's workout..."),
        String(localized: "Finalizing your results..."),
    ]
    private let checklist = [
        String(localized: "onboarding.generatingPlan.checklist.movement", defaultValue: "Movement", comment: "Checklist item label in the plan-generation loading card."),
        String(localized: "onboarding.generatingPlan.checklist.healthScore", defaultValue: "Health Score", comment: "Checklist item label in the plan-generation loading card."),
        String(localized: "onboarding.generatingPlan.checklist.workout", defaultValue: "Workout", comment: "Checklist item label in the plan-generation loading card."),
        String(localized: "onboarding.generatingPlan.checklist.activeRecovery", defaultValue: "Active Recovery", comment: "Checklist item label in the plan-generation loading card."),
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            progressRing

            VStack(spacing: 9) {
                Text("Creating your plan")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(SomaTokens.accent)
                Text("Setting everything up for you")
                    .font(.system(size: 30, weight: .bold, design: .serif).italic())
                    .multilineTextAlignment(.center)
                // The single status line that swaps in place -- no second,
                // separately-worded headline competing with it (that was
                // the build's actual bug: two status strings at once).
                Text(statusMessages[min(statusIndex, statusMessages.count - 1)])
                    .font(.system(size: 13))
                    .foregroundStyle(SomaTokens.ink3)
                    .animation(.easeInOut, value: statusIndex)
            }
            .padding(.horizontal, 24)

            CardView {
                Text("Daily recommendations for")
                    .font(.body.bold())
                ForEach(Array(checklist.enumerated()), id: \.offset) { index, item in
                    let isChecked = index < checkedCount
                    HStack {
                        Text(item)
                            .font(.subheadline.weight(isChecked ? .semibold : .regular))
                            .foregroundStyle(isChecked ? SomaTokens.ink : SomaTokens.ink4)
                        Spacer()
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .glassGel(.blue, cornerRadius: SomaTokens.rPill)
                        } else {
                            Circle()
                                .strokeBorder(SomaTokens.accent.opacity(0.3), lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                        }
                    }
                    .padding(.vertical, 2)
                    .animation(.easeInOut, value: checkedCount)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .somaBackground()
        .onAppear {
            guard !didStartWork else { return }
            didStartWork = true
            runSequence()
        }
        .task {
            await generateFirstRecommendation()
        }
    }

    // MARK: - Progress ring (10g: the ring IS the progress, no separate bar)

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(SomaTokens.accent.opacity(0.13), lineWidth: 6)
                .frame(width: 86, height: 86)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(SomaTokens.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 86, height: 86)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: percent)
            Text("\(percent)%")
                .font(.system(size: 27, weight: .bold, design: .serif).italic())
                .foregroundStyle(SomaTokens.ink)
                .contentTransition(.numericText())
        }
        .frame(width: 118, height: 118)
        .glassLens(cornerRadius: SomaTokens.rPill)
    }

    /// Runs in parallel with the fixed-duration loading animation above --
    /// whichever finishes last determines when the user actually sees the
    /// plan summary next, but the animation always plays out in full so
    /// this doesn't feel like a network spinner.
    private func generateFirstRecommendation() async {
        let snapshot = HealthKitManager.isAvailable
            ? await HealthKitManager.shared.fetchTodaysMetrics()
            : nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let today = formatter.string(from: Date())

        if let recommendation = try? await SupabaseClient.shared.invokeGenerateRecommendation(date: today, healthkit: snapshot) {
            appState.currentRecommendation = recommendation
            // Deliberately no markSentToday() here -- this never schedules
            // a local notification, so marking "sent" would wrongly
            // disable Trigger A/B's own guard for the rest of onboarding
            // day, the same bug fixed in HomeView.checkNow() (see its
            // doc comment).
        }
    }

    private func runSequence() {
        let totalDuration = 3.2
        let steps = 100
        let interval = totalDuration / Double(steps)

        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(step)) {
                percent = step
                statusIndex = min(step / (100 / statusMessages.count), statusMessages.count - 1)
                checkedCount = min(step / (100 / checklist.count), checklist.count)
                if step == steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        onFinished()
                    }
                }
            }
        }
    }
}
