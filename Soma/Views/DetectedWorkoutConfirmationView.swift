import SwiftUI

/// Home's confirmation prompt for a device-detected activity
/// (HomeView.evaluateDetectedWorkoutForConfirmation feeds this the day's
/// single best candidate via WorkoutTimelineEntry.confirmationCandidate).
///
/// Real feedback drove this screen into existence: HomeView used to write a
/// workout_log row for a detected session with no confirmation at all,
/// which meant an unconfirmed walk silently removed the user's workout plan
/// for the day. This view is the fix -- nothing gets logged until the user
/// explicitly says yes, and saying no (or ignoring it) leaves the readiness
/// card and AI plan generation exactly as if nothing had been detected.
///
/// A plain CardView, not a sheet: it sits directly in Home's scroll content
/// above the readiness card so the suggestion underneath stays visible and
/// tappable while this is still unanswered, rather than blocking it.
struct DetectedWorkoutConfirmationView: View {
    let entry: WorkoutTimelineEntry
    var onConfirm: () -> Void
    var onDecline: () -> Void

    var body: some View {
        CardView {
            Text(String(localized: "home.detectedWorkout.title", defaultValue: "We noticed an activity today", comment: "Home: title on the card asking whether a device-detected activity was the user's workout"))
                .font(.body.bold())
            Text(detailLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "home.detectedWorkout.question", defaultValue: "Was this your workout?", comment: "Home: question on the device-detected-activity confirmation card"))
                .font(.system(size: 14, weight: .semibold))

            // Stacked full-width, not side-by-side: both labels are full
            // sentences, and a half-width pair truncated badly (real device
            // check: "Yes, that was my..." / "No, show me a wo..."). Same
            // primary-CTA-then-secondary-link shape as readinessCard's own
            // "Start workout" / "Log a different activity" pairing below.
            SomaButton(
                title: LocalizedStringKey(String(localized: "home.detectedWorkout.confirmButton", defaultValue: "Yes, that was my workout", comment: "Home: confirms a device-detected activity as today's workout")),
                size: .md,
                variant: .primary,
                action: onConfirm
            )
            Button(action: onDecline) {
                Text(String(localized: "home.detectedWorkout.declineButton", defaultValue: "No, show me a workout plan", comment: "Home: declines a device-detected activity, keeping the AI workout plan available"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
            }
            .buttonStyle(.plain)
        }
    }

    /// Same "source — duration — kcal" shape as the timeline card's own
    /// entry row (HomeView's timelineCard), so this reads as the same
    /// activity the user can already see listed there.
    private var detailLine: String {
        if let calories = entry.calories {
            return String(localized: "home.detectedWorkout.detailWithCalories", defaultValue: "\(entry.title) — \(entry.sourceDisplayName) — \(entry.durationMinutes) min — \(calories.formatted()) kcal", comment: "Home: detected-activity confirmation card detail line, with calories")
        }
        return String(localized: "home.detectedWorkout.detailNoCalories", defaultValue: "\(entry.title) — \(entry.sourceDisplayName) — \(entry.durationMinutes) min", comment: "Home: detected-activity confirmation card detail line, no calories reported")
    }
}
