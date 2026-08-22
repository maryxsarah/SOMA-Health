import Combine
import SwiftUI
import UIKit

/// Full-screen, one-step-at-a-time walkthrough of a MealRecommendation's
/// steps -- large type readable from arm's length across a kitchen, no
/// scrolling required mid-step. Keeps the screen awake for the duration
/// (a recipe with a 15-minute bake step is exactly the case where the
/// screen would otherwise lock mid-cook) and hands that back the moment
/// this view goes away, however it goes away.
struct CookModeView: View {
    let mealName: String
    let steps: [MealRecommendationStep]
    /// Called once the user finishes the last step (taps "Done cooking")
    /// -- lets the presenter (MealRecommendationView) offer "Log this
    /// meal" right at the moment of actually finishing, not before.
    var onFinish: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    /// Wall-clock end time for the current step's timer -- nil means
    /// idle (never started, or reset). Deliberately not a plain
    /// decrementing counter: driving the display off `endDate.
    /// timeIntervalSinceNow` on every tick means the countdown is still
    /// correct even if the app was backgrounded and resumed mid-timer,
    /// same reasoning NotificationManager's own scheduled alert relies on.
    @State private var timerEndDate: Date?
    @State private var remainingSeconds: Int = 0
    /// Guards the "time's up" haptic to fire exactly once per timer run,
    /// not on every tick after remainingSeconds reaches 0.
    @State private var timerDidFinish = false
    private let timerTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isLastStep: Bool { index == steps.count - 1 }
    private var currentStepDuration: Int? { steps[index].durationSeconds }
    private var isTimerRunning: Bool { timerEndDate != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            progressBar
            Spacer()
            VStack(spacing: 20) {
                stepText
                stepTimerView
            }
            .id(index)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            Spacer()
            controls
        }
        .padding(20)
        .somaBackground()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            NotificationManager.shared.cancelCookingTimer()
        }
        .onChange(of: index) { _, _ in resetTimer() }
        .onReceive(timerTick) { _ in tick() }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink3)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(SomaTokens.surface3))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(mealName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.ink2)
                .lineLimit(1)
            Spacer()
            // Balances the close button so the title stays visually
            // centered -- an invisible same-size spacer, not a second
            // control.
            Color.clear.frame(width: 32, height: 32)
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "cookMode.progress.stepLabel", defaultValue: "Step \(index + 1) of \(steps.count)", comment: "Step progress indicator in cook mode, e.g. 'Step 2 of 5'"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SomaTokens.ink3)
                .padding(.top, 18)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SomaTokens.surface3)
                    Capsule()
                        .fill(SomaTokens.accent)
                        .frame(width: geo.size.width * CGFloat(index + 1) / CGFloat(max(steps.count, 1)))
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
        }
    }

    private var stepText: some View {
        Text(steps[index].text)
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(SomaTokens.ink)
            .multilineTextAlignment(.leading)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Renders only when this step actually has a wait attached
    /// (durationSeconds != nil) -- most steps (chopping, seasoning) show
    /// no timer control at all, same as today.
    @ViewBuilder
    private var stepTimerView: some View {
        if let duration = currentStepDuration {
            VStack(spacing: 12) {
                Text(Self.formattedClock(isTimerRunning ? remainingSeconds : duration))
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(timerDidFinish ? SomaTokens.accent : SomaTokens.ink)
                if timerDidFinish {
                    Label(
                        String(localized: "cookMode.timer.done", defaultValue: "Time's up", comment: "Shown in cook mode once a step's timer reaches zero"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
                    SomaButton(title: LocalizedStringKey(String(localized: "cookMode.timer.reset", defaultValue: "Reset timer", comment: "Button to reset a finished or running cook mode step timer")), size: .md, variant: .secondary) {
                        resetTimer()
                    }
                } else if isTimerRunning {
                    SomaButton(title: LocalizedStringKey(String(localized: "cookMode.timer.reset", defaultValue: "Reset timer", comment: "Button to reset a finished or running cook mode step timer")), size: .md, variant: .secondary) {
                        resetTimer()
                    }
                } else {
                    SomaButton(title: LocalizedStringKey(String(localized: "cookMode.timer.start", defaultValue: "Start timer", comment: "Button to start a cook mode step's countdown timer")), size: .md, variant: .primary) {
                        startTimer(seconds: duration)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if index > 0 {
                SomaButton(title: "Back", size: .lg, variant: .secondary) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { index -= 1 }
                }
            }
            let nextButtonTitle = LocalizedStringKey(isLastStep
                ? String(localized: "cookMode.controls.doneCooking", defaultValue: "Done cooking", comment: "Button on the last cook mode step to finish cooking")
                : String(localized: "cookMode.controls.nextStep", defaultValue: "Next step", comment: "Button to advance to the next cook mode step"))
            SomaButton(title: nextButtonTitle, size: .lg, variant: .primary) {
                if isLastStep {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onFinish()
                    dismiss()
                } else {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { index += 1 }
                }
            }
        }
    }

    // MARK: - Timer

    private func startTimer(seconds: Int) {
        timerEndDate = Date().addingTimeInterval(TimeInterval(seconds))
        remainingSeconds = seconds
        timerDidFinish = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await NotificationManager.shared.scheduleCookingTimer(seconds: TimeInterval(seconds), stepText: steps[index].text) }
    }

    private func resetTimer() {
        timerEndDate = nil
        remainingSeconds = 0
        timerDidFinish = false
        NotificationManager.shared.cancelCookingTimer()
    }

    private func tick() {
        guard let timerEndDate, !timerDidFinish else { return }
        remainingSeconds = max(0, Int(timerEndDate.timeIntervalSinceNow.rounded(.up)))
        if remainingSeconds == 0 {
            timerDidFinish = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private static func formattedClock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    CookModeView(
        mealName: "Sheet-Pan Chicken and Veggies",
        steps: [
            MealRecommendationStep(text: "Preheat the oven to 200°C/400°F."),
            MealRecommendationStep(text: "Toss the chicken thighs and chopped vegetables with a tablespoon of olive oil, salt, and pepper on a sheet pan."),
            MealRecommendationStep(text: "Roast for 25-30 minutes, until the chicken reaches 165°F internally and the vegetables are tender.", durationSeconds: 1500),
            MealRecommendationStep(text: "Flip halfway through, after about 12 minutes.", durationSeconds: 720),
            MealRecommendationStep(text: "Rest for 5 minutes, then plate and serve.", durationSeconds: 300),
        ]
    )
}
