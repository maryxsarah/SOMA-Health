import Foundation

/// Deterministic "how far into your plan are you" read for the goal-
/// progress bar -- reuses GoalPace.estimatedMonths (the same rule-based
/// timeline already shown live during onboarding's GoalPaceQuestionView)
/// rather than inventing a second estimate. Real elapsed time against a
/// real (if rough) estimate -- never a fabricated percentage.
struct GoalJourneyProgress {
    let daysElapsed: Int
    let estimatedTotalDays: Int
    /// Clamped 0...1 -- a user who's gone past their estimated timeline
    /// still sees a full bar (not >100%), with daysElapsed itself telling
    /// the honest story if they check the exact numbers.
    let fraction: Double
    /// False when the delta is too small to responsibly estimate a timeline --
    /// likely a stale weight target that was never updated to match the goal photo.
    let hasReliableEstimate: Bool

    private static let averageDaysPerMonth = 30
    /// Below this, a weight-only estimate is more likely stale than honest.
    private static let minReliableDeltaKg = 3.0

    /// nil when any required input is missing -- weightKg/desiredWeightKg/
    /// goalPace are all optional profile fields (goalPace especially: only
    /// collected when the user set a desired weight during onboarding).
    /// Never guesses a start point or a pace that wasn't actually chosen.
    static func compute(
        createdAt: String?,
        weightKg: Double?,
        desiredWeightKg: Double?,
        goalPace: GoalPace?
    ) -> GoalJourneyProgress? {
        guard let createdAt, let weightKg, let desiredWeightKg, let goalPace,
              let startDate = parseISO8601(createdAt)
        else { return nil }

        let deltaKg = desiredWeightKg - weightKg
        let estimatedMonths = GoalPace.estimatedMonths(deltaKg: deltaKg, pace: goalPace)
        let estimatedTotalDays = max(1, estimatedMonths * averageDaysPerMonth)

        let daysElapsed = max(0, Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0)
        let fraction = min(1.0, Double(daysElapsed) / Double(estimatedTotalDays))
        let hasReliableEstimate = abs(deltaKg) >= minReliableDeltaKg

        return GoalJourneyProgress(
            daysElapsed: daysElapsed, estimatedTotalDays: estimatedTotalDays, fraction: fraction,
            hasReliableEstimate: hasReliableEstimate
        )
    }

    /// Postgres timestamptz comes back as ISO8601 with fractional seconds
    /// (e.g. "2026-07-15T10:23:45.123456+00:00") -- tries with fractional
    /// seconds first, falls back to without, rather than failing outright
    /// on a format variation.
    private static func parseISO8601(_ raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
