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
    let steps: [String]
    /// Called once the user finishes the last step (taps "Done cooking")
    /// -- lets the presenter (MealRecommendationView) offer "Log this
    /// meal" right at the moment of actually finishing, not before.
    var onFinish: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private var isLastStep: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            progressBar
            Spacer()
            stepText
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
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
            Text("Step \(index + 1) of \(steps.count)")
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
        Text(steps[index])
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(SomaTokens.ink)
            .multilineTextAlignment(.leading)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if index > 0 {
                SomaButton(title: "Back", size: .lg, variant: .secondary) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { index -= 1 }
                }
            }
            SomaButton(title: isLastStep ? "Done cooking" : "Next step", size: .lg, variant: .primary) {
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
}

#Preview {
    CookModeView(
        mealName: "Sheet-Pan Chicken and Veggies",
        steps: [
            "Preheat the oven to 200°C/400°F.",
            "Toss the chicken thighs and chopped vegetables with a tablespoon of olive oil, salt, and pepper on a sheet pan.",
            "Roast for 25-30 minutes, until the chicken reaches 165°F internally and the vegetables are tender.",
            "Rest for 5 minutes, then plate and serve.",
        ]
    )
}
