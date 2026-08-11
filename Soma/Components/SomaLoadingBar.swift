import SwiftUI

/// Shared "still working, and it feels good" indicator -- an animated
/// indeterminate progress bar (neither use site has a real percentage to
/// report) with optional rotating supportive text underneath. Same visual
/// language wherever the app has to make someone wait: GoalBodyProgressView's
/// initial load and ExerciseDetailView's media area, so loading reads as
/// one system rather than two different spinners.
struct SomaLoadingBar: View {
    var messages: [String] = []
    /// Caller-controlled width for the bar itself (the text wraps to fit
    /// whatever container it's placed in) -- ExerciseDetailView wants a
    /// narrow bar inside a small media placeholder, GoalBodyProgressView
    /// wants one closer to full-width.
    var barWidth: CGFloat = 160

    @State private var barProgress: CGFloat = 0.12
    @State private var messageIndex = 0

    var body: some View {
        VStack(spacing: 12) {
            bar
            if !messages.isEmpty {
                Text(messages[messageIndex])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
                    .id(messageIndex)
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Eases up toward "almost done," never claims to actually
            // finish -- an indeterminate wait dressed as a real one would
            // be worse than a plain spinner the moment it's noticeably
            // wrong. repeatForever ties the animation to this view's own
            // lifetime, so it stops cleanly when the view disappears.
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                barProgress = 0.92
            }
        }
        .task {
            guard messages.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    messageIndex = (messageIndex + 1) % messages.count
                }
            }
        }
    }

    private var bar: some View {
        Capsule()
            .fill(SomaTokens.surface3)
            .frame(width: barWidth, height: 6)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [SomaTokens.accent, SomaTokens.accentDeep],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth * barProgress, height: 6)
            }
    }
}

extension SomaLoadingBar {
    /// Rotates while GoalBodyProgressView loads -- affirming and forward-
    /// looking, matching that screen's "SOMA is how you get there" framing
    /// rather than generic "please wait" copy.
    static let goalProgressMessages = [
        String(localized: "loadingBar.goalProgress.0", defaultValue: "You're on track to reach your goal.", comment: "Rotating motivational message shown while a goal-progress estimate loads"),
        String(localized: "loadingBar.goalProgress.1", defaultValue: "Every day you commit is a day you win.", comment: "Rotating motivational message shown while a goal-progress estimate loads"),
        String(localized: "loadingBar.goalProgress.2", defaultValue: "Consistency beats perfection.", comment: "Rotating motivational message shown while a goal-progress estimate loads"),
        String(localized: "loadingBar.goalProgress.3", defaultValue: "Small steps, real progress.", comment: "Rotating motivational message shown while a goal-progress estimate loads"),
        String(localized: "loadingBar.goalProgress.4", defaultValue: "Showing up today is what changes tomorrow.", comment: "Rotating motivational message shown while a goal-progress estimate loads"),
        String(localized: "loadingBar.goalProgress.5", defaultValue: "Your future self is already proud of you.", comment: "Rotating motivational message shown while a goal-progress estimate loads"),
    ]

    /// Rotates while parse-meal-text estimates a logged meal -- lighthearted
    /// food trivia rather than motivational copy, since this wait is a
    /// quick utility step, not a milestone moment. Callers should pass
    /// `.shuffled()` so repeated estimates in one sitting don't always open
    /// on the same line.
    static let mealFunFacts = [
        String(localized: "loadingBar.mealFact.0", defaultValue: "Honey never spoils -- archaeologists have found 3,000-year-old honey that's still edible.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
        String(localized: "loadingBar.mealFact.1", defaultValue: "Bananas are berries. Strawberries, botanically, are not.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
        String(localized: "loadingBar.mealFact.2", defaultValue: "Carrots were originally purple before the Dutch bred the orange ones.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
        String(localized: "loadingBar.mealFact.3", defaultValue: "Peanuts aren't nuts -- they're legumes.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
        String(localized: "loadingBar.mealFact.4", defaultValue: "Avocados are technically a single-seeded berry.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
        String(localized: "loadingBar.mealFact.5", defaultValue: "Apples float because they're about 25% air.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
        String(localized: "loadingBar.mealFact.6", defaultValue: "Chocolate was once used as currency by the Aztecs.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
        String(localized: "loadingBar.mealFact.7", defaultValue: "An egg's shell color depends on the hen's breed, not its nutrition.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
        String(localized: "loadingBar.mealFact.8", defaultValue: "Chewing celery burns about as many calories as it contains -- close to a wash.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
        String(localized: "loadingBar.mealFact.9", defaultValue: "Crunching your food louder can genuinely make it taste better, per actual studies.", comment: "Rotating food-trivia fact shown while a logged meal is estimated"),
    ]
}

#Preview {
    VStack(spacing: 40) {
        SomaLoadingBar(messages: SomaLoadingBar.goalProgressMessages, barWidth: 240)
        SomaLoadingBar(barWidth: 120)
    }
    .padding()
}
