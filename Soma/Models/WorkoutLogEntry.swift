import Foundation

/// Mirrors a `workout_log` row -- one entry per workout the user tapped
/// "Log workout" on.
struct WorkoutLogEntry: Codable, Identifiable {
    let id: String
    let date: String
    let title: String
    let bodyPart: String
    let category: String
    let completedAt: String
    let feedback: String?
    /// The AI-generated plan actually shown when this workout was logged,
    /// snapshotted at log time -- nil for entries logged before this
    /// column existed. Lets Training History show real exercise-level
    /// detail per day instead of just title/body_part.
    let planSnapshot: AIWorkoutPlan?
    /// Real workout start/end, distinct from `completedAt` (the log
    /// action's own timestamp) -- nil for entries logged before these
    /// columns existed, or logged without a reliable start time. Raw ISO
    /// 8601 strings, same convention as `completedAt`, parsed at the point
    /// of use rather than decoded as Date (this app doesn't set a custom
    /// JSONDecoder date strategy).
    let startedAt: String?
    let endedAt: String?
    /// Self-reported "how it felt", set at log time or edited afterward
    /// (CompletedWorkoutView's "Edit this log") -- nil for entries logged
    /// before this column existed, or never rated. UI/copy layer only: see
    /// `WorkoutFeelRating.consequence`.
    let feelRating: WorkoutFeelRating?
    /// "ai_plan" (an AI-generated suggestion/plan, the default -- every
    /// row created before this column existed really was this) or
    /// "manual" (a sport/activity the user logged themselves, see
    /// LogManualWorkoutView). Decides which detail screen HomeView routes
    /// to when the user taps today's logged workout.
    let source: String
    /// Calorie hero stat on CompletedWorkoutView -- nil until the lazy
    /// backfill (CompletedWorkoutView.load()) resolves it, either from a
    /// real HealthKit/wearable reading over this log's started_at/ended_at
    /// window, or (see `caloriesEstimated`) a MET-based estimate. Never a
    /// fabricated placeholder: nil renders as an honest "--", not 0.
    var caloriesBurned: Int? = nil
    /// True only when `caloriesBurned` came from WorkoutCalorieEstimator
    /// rather than a measured device reading -- gates the "Estimated"
    /// label so an estimate is never shown as if it were measured.
    var caloriesEstimated: Bool = false
    /// The resolved "why this workout today" text, frozen the first time
    /// WorkoutReasonResolver ever ran for this log -- see the
    /// 20260809020000 migration's comment and WorkoutReasonResolver.swift.
    var reasonSnapshot: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, date, title, category, feedback, source
        case bodyPart = "body_part"
        case completedAt = "completed_at"
        case planSnapshot = "plan_snapshot"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case feelRating = "feel_rating"
        case caloriesBurned = "calories_burned"
        case caloriesEstimated = "calories_estimated"
        case reasonSnapshot = "reason_snapshot"
    }
}

/// The 3 "how it felt" chips on CompletedWorkoutView -- fixed vocabulary,
/// matching the `workout_log.feel_rating` check constraint.
enum WorkoutFeelRating: String, Codable, CaseIterable, Identifiable {
    case easy
    case hardButGood = "hard_but_good"
    case tooMuch = "too_much"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .hardButGood: "Hard but good"
        case .tooMuch: "Too much"
        }
    }

    /// Fixed, template-driven copy explaining the effect on upcoming days --
    /// same "no LLM freeform" convention as RecommendationReason's own
    /// tomorrowTip. This is a UI/copy layer only: it is not read by
    /// generate-recommendation's actual capping logic.
    var consequence: String {
        switch self {
        case .easy:
            "Soma will nudge tomorrow's intensity up a notch if your recovery data supports it."
        case .hardButGood:
            "Soma will keep the next few days as planned -- this looked like the right effort for today."
        case .tooMuch:
            "Soma will ease tomorrow toward Moderate or Light, even if recovery data alone would suggest more."
        }
    }
}
