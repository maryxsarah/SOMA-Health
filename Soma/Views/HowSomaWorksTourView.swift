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

    /// Each field is built with `String(localized:)` rather than typed as
    /// `LocalizedStringKey` -- a plain `String` field initialized from a
    /// literal, then read back via `Text(card.field)`, bypasses the
    /// catalog silently (BUG-127, docs/bug-log.md): `Text(String)` is
    /// SwiftUI's verbatim initializer, so it never did a lookup no matter
    /// what was in Localizable.xcstrings.
    private static let cards: [Card] = [
        Card(
            icon: "waveform.path.ecg",
            title: String(localized: "howSomaWorks.dailyReadiness.title", defaultValue: "Daily readiness", comment: "How Soma Works tour: card title for the daily readiness feature"),
            description: String(localized: "howSomaWorks.dailyReadiness.description", defaultValue: "Every morning, Soma reads your connected wearable -- sleep, HRV, resting heart rate -- and turns it into one honest effort level for today: rest, light, moderate, or push hard.", comment: "How Soma Works tour: card description for the daily readiness feature"),
            whereToFind: String(localized: "howSomaWorks.dailyReadiness.whereToFind", defaultValue: "Always the first card on Home. Tap \"Why this?\" to see the real numbers behind it.", comment: "How Soma Works tour: where-to-find line for the daily readiness feature")
        ),
        Card(
            icon: "checklist",
            title: String(localized: "howSomaWorks.dailyChecklist.title", defaultValue: "Daily checklist", comment: "How Soma Works tour: card title for the daily checklist feature"),
            description: String(localized: "howSomaWorks.dailyChecklist.description", defaultValue: "The exact card you tapped this from. A short list of real daily habits -- log a meal, hit your step goal, check in on your mood -- that keeps momentum honest, one real day at a time.", comment: "How Soma Works tour: card description for the daily checklist feature"),
            whereToFind: String(localized: "howSomaWorks.dailyChecklist.whereToFind", defaultValue: "On Home, right below your weekly progress.", comment: "How Soma Works tour: where-to-find line for the daily checklist feature")
        ),
        Card(
            icon: "figure.strengthtraining.traditional",
            title: String(localized: "howSomaWorks.workouts.title", defaultValue: "Workouts", comment: "How Soma Works tour: card title for the workouts feature"),
            description: String(localized: "howSomaWorks.workouts.description", defaultValue: "Start today's AI-built plan, snap a photo of a gym to get one built around the equipment you can see, or log any activity yourself. A completed session always shows your real effort, calories, and how it went.", comment: "How Soma Works tour: card description for the workouts feature"),
            whereToFind: String(localized: "howSomaWorks.workouts.whereToFind", defaultValue: "\"Start workout\" on your readiness card, or \"Somewhere else today?\" to scan a gym.", comment: "How Soma Works tour: where-to-find line for the workouts feature")
        ),
        Card(
            icon: "fork.knife",
            title: String(localized: "howSomaWorks.nutrition.title", defaultValue: "Nutrition", comment: "How Soma Works tour: card title for the nutrition feature"),
            description: String(localized: "howSomaWorks.nutrition.description", defaultValue: "See your daily calorie and macro targets, log meals as you eat, or ask \"What can I make?\" for a real recipe built only from what's actually in your kitchen.", comment: "How Soma Works tour: card description for the nutrition feature"),
            whereToFind: String(localized: "howSomaWorks.nutrition.whereToFind", defaultValue: "The Nutrition row on Home.", comment: "How Soma Works tour: where-to-find line for the nutrition feature")
        ),
        Card(
            icon: "chart.bar.fill",
            title: String(localized: "howSomaWorks.dashboard.title", defaultValue: "Dashboard", comment: "How Soma Works tour: card title for the dashboard feature"),
            description: String(localized: "howSomaWorks.dashboard.description", defaultValue: "Every metric Soma reads -- sleep, HRV, resting heart rate, mood, weight -- plotted over time, so you can see a real trend instead of just today's snapshot.", comment: "How Soma Works tour: card description for the dashboard feature"),
            whereToFind: String(localized: "howSomaWorks.dashboard.whereToFind", defaultValue: "Tap \"Dashboard\" at the top of Home.", comment: "How Soma Works tour: where-to-find line for the dashboard feature")
        ),
        Card(
            icon: "photo.on.rectangle.angled",
            title: String(localized: "howSomaWorks.goalProgress.title", defaultValue: "Goal progress", comment: "How Soma Works tour: card title for the goal progress feature"),
            description: String(localized: "howSomaWorks.goalProgress.description", defaultValue: "Add a photo of the body you're working toward and one of where you are today. Soma builds your plan around closing that real gap, and shows you real progress along the way.", comment: "How Soma Works tour: card description for the goal progress feature"),
            whereToFind: String(localized: "howSomaWorks.goalProgress.whereToFind", defaultValue: "\"Your progress\" on Home, once you've added a goal photo.", comment: "How Soma Works tour: where-to-find line for the goal progress feature")
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
                PillButton(title: LocalizedStringKey(String(localized: "howSomaWorks.finishButton", defaultValue: "Got it -- let's go", comment: "Button that dismisses the How Soma Works tour after its last card"))) {
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
