import Foundation

/// Resolves the text CompletedWorkoutView shows up front (never behind a
/// SomaDisclosure -- this is the app's biggest post-workout trust moment).
/// Never returns an empty string: every branch ends in real, honest copy.
///
/// A persisted `log.reasonSnapshot` always wins outright -- it's frozen
/// from the first time this resolver ever ran for that log (see the
/// 20260809020000 migration's own comment for why that matters: a same-day
/// daily_recommendation re-generation must not retroactively change what a
/// user is told about a workout they already did). This function is what
/// computes that snapshot in the first place, via CompletedWorkoutView's
/// lazy backfill, and what a legacy pre-migration row falls back to live.
///
/// Every source gets retrospective IMPACT copy (item 1 fix, completed):
/// prescriptive "why was this suggested" copy never appears on a completed
/// object -- a retrospective screen answers what it counted toward and how
/// it changes tomorrow, not why a plan was picked. The day's forward
/// rationale still lives where plans live (RecommendationDetailView's
/// "Why this?" disclosure), frozen there by its own snapshot.
enum WorkoutReasonResolver {
    static func reason(for log: WorkoutLogEntry, recommendation: DailyRecommendation?, snapshots: [DailySnapshotRow], dayLoadState: DayLoadState) -> String {
        if let persisted = log.reasonSnapshot, !persisted.isEmpty {
            return persisted
        }
        return impactNote(source: log.source, dayLoadState: dayLoadState)
    }

    /// Retrospective "what this did", not a plan-screen rationale --
    /// internal (not private) so the log-time paths can freeze this exact
    /// text into `reason_snapshot` the moment a workout is logged, instead
    /// of waiting for CompletedWorkoutView's first-open backfill (spec:
    /// rationale is frozen when the session is created, so a same-day
    /// recommendation regeneration can never rewrite it).
    static func impactNote(source: String, dayLoadState: DayLoadState) -> String {
        switch source {
        case "ai_plan":
            switch dayLoadState {
            case .fulfilled, .overreached:
                return String(localized: "workoutReason.impact.aiPlan.done", defaultValue: "Today's plan, completed -- daily target met. Tomorrow's recommendation builds on this.", comment: "Completed workout: retrospective impact note for a completed AI-plan session that met today's activity target")
            case .pending, .partiallyDone:
                return String(localized: "workoutReason.impact.aiPlan.partial", defaultValue: "Today's plan, logged. Counted toward your weekly target -- tomorrow's recommendation builds on it.", comment: "Completed workout: retrospective impact note for a completed AI-plan session that didn't fully close today's activity target")
            }
        case "device_detected":
            switch dayLoadState {
            case .fulfilled, .overreached:
                return String(localized: "workoutReason.impact.deviceDetected.done", defaultValue: "Counted toward your weekly volume. Tomorrow, Soma will lower the load -- you've already closed today's quota.", comment: "Completed workout: retrospective impact note for an auto-detected session that met or exceeded today's activity target")
            case .pending, .partiallyDone:
                return String(localized: "workoutReason.impact.deviceDetected.partial", defaultValue: "Detected automatically from a connected device, outside today's suggested plan. Counted toward your weekly volume.", comment: "Completed workout: retrospective impact note for an auto-detected session that didn't fully close today's activity target")
            }
        case "manual":
            return String(localized: "workoutReason.impact.manual", defaultValue: "Your workout, outside Soma's plan. Counted in weekly load.", comment: "Completed workout: retrospective impact note for a manually-logged session")
        default:
            return String(localized: "workoutReason.impact.other", defaultValue: "This wasn't today's suggested plan. Counted in weekly load.", comment: "Completed workout: retrospective impact note for a session logged from an unrecognized source")
        }
    }

}
