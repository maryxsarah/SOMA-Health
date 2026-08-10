import SwiftUI

/// "How Soma Works" -- a calm, factual tour of what's actually in the
/// app, one card per real feature area. Reached two ways: the onboarding
/// checklist's "See how Soma works" item (first time, via HomeView), and
/// a quiet refresher row in ProfileView's Account tab (any time after).
/// Same view either way -- only what `onFinish` does differs per caller.
///
/// Every claim on every card was checked against this build before being
/// written (2026-08-10), not assumed:
///   - Daily readiness / Daily checklist / Workouts / Nutrition / Dashboard
///     are all unconditional, always-on screens -- no Config flag gates
///     any of them.
///   - Goal progress is real and live (Config.enableBodyPhotoUpload,
///     currently true) -- HomeView's own goalProgressRow already degrades
///     gracefully to "Add your date of birth" for a user who isn't
///     age-confirmed yet, so pointing at it here is honest even for a
///     user who can't use it on day one.
///   - Deliberately NOT a card: Sport Goals and Cycle Tracking. Both are
///     real (Config.enableSportGoals / enableCyclePhaseTracking), but
///     Sport Goals' actual on/off switch is server-side (empty catalog =
///     dark for that deployment) and Cycle Tracking is a Profile-only
///     opt-in most users haven't turned on -- neither is a safe "this is
///     just how the app works for you" claim the way the six below are.
///
/// No coach/mascot persona, no gamified badge language (standing rule for
/// this app) -- copy states what each screen does, not "unlock" language.
struct HowSomaWorksTourView: View {
    /// Called once, when the user taps the final card's "Got it -- let's
    /// go" button. The checklist-triggered call site marks the checklist
    /// item complete here; the Profile refresher call site just dismisses
    /// -- see each's own call site for why.
    let onFinish: () -> Void

    private struct Card {
        let icon: String
        let title: String
        let description: String
        let whereToFind: String
    }

    private static let cards: [Card] = [
        Card(
            icon: "waveform.path.ecg",
            title: "Daily readiness",
            description: "Every morning, Soma reads your connected wearable -- sleep, HRV, resting heart rate -- and turns it into one honest effort level for today: rest, light, moderate, or push hard.",
            whereToFind: "Always the first card on Home. Tap \"Why this?\" to see the real numbers behind it."
        ),
        Card(
            icon: "checklist",
            title: "Daily checklist",
            description: "The exact card you tapped this from. A short list of real daily habits -- log a meal, hit your step goal, check in on your mood -- that keeps momentum honest, one real day at a time.",
            whereToFind: "On Home, right below your weekly progress."
        ),
        Card(
            icon: "figure.strengthtraining.traditional",
            title: "Workouts",
            description: "Start today's AI-built plan, snap a photo of a gym to get one built around the equipment you can see, or log any activity yourself. A completed session always shows your real effort, calories, and how it went.",
            whereToFind: "\"Start workout\" on your readiness card, or \"Somewhere else today?\" to scan a gym."
        ),
        Card(
            icon: "fork.knife",
            title: "Nutrition",
            description: "See your daily calorie and macro targets, log meals as you eat, or ask \"What can I make?\" for a real recipe built only from what's actually in your kitchen.",
            whereToFind: "The Nutrition row on Home."
        ),
        Card(
            icon: "chart.bar.fill",
            title: "Dashboard",
            description: "Every metric Soma reads -- sleep, HRV, resting heart rate, mood, weight -- plotted over time, so you can see a real trend instead of just today's snapshot.",
            whereToFind: "Tap \"Dashboard\" at the top of Home."
        ),
        Card(
            icon: "photo.on.rectangle.angled",
            title: "Goal progress",
            description: "Add a photo of the body you're working toward and one of where you are today. Soma builds your plan around closing that real gap, and shows you real progress along the way.",
            whereToFind: "\"Your progress\" on Home, once you've added a goal photo."
        ),
    ]

    @State private var page = 0
    /// One-time reveal for the whole sheet (not per-card, so re-swiping
    /// back and forth never re-triggers it) -- same
    /// .spring(response: 0.75, dampingFraction: 0.75) idiom
    /// GoalTrajectoryChartView's own onAppear reveal uses.
    @State private var hasAppeared = false

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(Self.cards.enumerated()), id: \.offset) { index, card in
                cardView(card, isLast: index == Self.cards.count - 1)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .somaBackground()
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.75)) {
                hasAppeared = true
            }
        }
    }

    private func cardView(_ card: Card, isLast: Bool) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon-in-plate: scanRowBody's exact visual pattern
            // (SomaTokens.accentSoft plate, SomaTokens.accent icon),
            // scaled up for a hero card instead of a compact list row.
            Image(systemName: card.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SomaTokens.accent)
                .frame(width: 76, height: 76)
                .background(RoundedRectangle(cornerRadius: SomaTokens.r2XL, style: .continuous).fill(SomaTokens.accentSoft))
                .scaleEffect(hasAppeared ? 1 : 0.7)
                .opacity(hasAppeared ? 1 : 0)

            Text(card.title)
                .font(Theme.display)
                .multilineTextAlignment(.center)

            Text(card.description)
                .font(.system(size: 15))
                .foregroundStyle(SomaTokens.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.top, 1)
                Text(card.whereToFind)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(SomaTokens.ink3)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 36)

            Spacer()
            Spacer()

            if isLast {
                PillButton(title: "Got it -- let's go") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onFinish()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            } else {
                // Keeps every card's vertical rhythm identical whether or
                // not it has the button, so swiping between cards doesn't
                // visibly jump.
                Color.clear.frame(height: 50 + 40)
            }
        }
    }
}

#Preview {
    HowSomaWorksTourView(onFinish: {})
}
