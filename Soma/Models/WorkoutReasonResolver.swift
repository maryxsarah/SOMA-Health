import Foundation

/// Resolves the "why this workout today" text CompletedWorkoutView shows
/// up front (never behind a SomaDisclosure -- this is the app's biggest
/// post-workout trust moment). Never returns an empty string: every branch
/// ends in real, honest copy.
///
/// A persisted `log.reasonSnapshot` always wins outright -- it's frozen
/// from the first time this resolver ever ran for that log (see the
/// 20260809020000 migration's own comment for why that matters: a same-day
/// daily_recommendation re-generation must not retroactively change what a
/// user is told about a workout they already did). This function is what
/// computes that snapshot in the first place, via CompletedWorkoutView's
/// lazy backfill, and what a legacy pre-migration row falls back to live.
enum WorkoutReasonResolver {
    static func reason(for log: WorkoutLogEntry, recommendation: DailyRecommendation?, snapshots: [DailySnapshotRow]) -> String {
        if let persisted = log.reasonSnapshot, !persisted.isEmpty {
            return persisted
        }
        guard let recommendation else {
            return fallback(source: log.source)
        }
        let explanation = recommendation.reason.explanation(snapshots: snapshots)
        // ai_plan is literally what the recommendation produced -- the
        // explanation alone is the whole story. Manual/device-detected
        // sessions are real, but weren't the suggested plan, so the day's
        // real readiness read is still true and worth showing -- it just
        // needs an honest caveat that this specific session diverged from it.
        guard log.source != "ai_plan" else { return explanation }
        return explanation + " " + offPlanNote(source: log.source)
    }

    private static func offPlanNote(source: String) -> String {
        switch source {
        case "manual": "You logged this yourself, outside today's suggested plan."
        case "device_detected": "Detected automatically from a connected device, outside today's suggested plan."
        default: "This wasn't today's suggested plan."
        }
    }

    /// No daily_recommendation row exists at all for this log's date --
    /// still an honest, specific line, never a blank card.
    private static func fallback(source: String) -> String {
        switch source {
        case "manual": "You logged this yourself -- no readiness read is on file for this day."
        case "device_detected": "Detected automatically from a connected device -- no readiness read is on file for this day."
        default: "No readiness read is on file for this day."
        }
    }
}
