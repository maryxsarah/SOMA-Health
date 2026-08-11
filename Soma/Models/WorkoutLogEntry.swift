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

    enum CodingKeys: String, CodingKey {
        case id, date, title, category, feedback
        case bodyPart = "body_part"
        case completedAt = "completed_at"
        case planSnapshot = "plan_snapshot"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case feelRating = "feel_rating"
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
        case .easy: String(localized: "workoutFeelRating.easy", defaultValue: "Easy", comment: "Short chip label for a workout that felt easy")
        case .hardButGood: String(localized: "workoutFeelRating.hardButGood", defaultValue: "Hard but good", comment: "Short chip label for a workout that was hard but felt good")
        case .tooMuch: String(localized: "workoutFeelRating.tooMuch", defaultValue: "Too much", comment: "Short chip label for a workout that was too much")
        }
    }

    /// Fixed, template-driven copy explaining the effect on upcoming days --
    /// same "no LLM freeform" convention as RecommendationReason's own
    /// tomorrowTip. This is a UI/copy layer only: it is not read by
    /// generate-recommendation's actual capping logic.
    var consequence: String {
        switch self {
        case .easy:
            String(localized: "workoutFeelRating.easyConsequence", defaultValue: "Soma will nudge tomorrow's intensity up a notch if your recovery data supports it.", comment: "Longer sentence explaining how rating a workout 'Easy' affects tomorrow's plan")
        case .hardButGood:
            String(localized: "workoutFeelRating.hardButGoodConsequence", defaultValue: "Soma will keep the next few days as planned -- this looked like the right effort for today.", comment: "Longer sentence explaining how rating a workout 'Hard but good' affects upcoming days' plan")
        case .tooMuch:
            String(localized: "workoutFeelRating.tooMuchConsequence", defaultValue: "Soma will ease tomorrow toward Moderate or Light, even if recovery data alone would suggest more.", comment: "Longer sentence explaining how rating a workout 'Too much' affects tomorrow's plan")
        }
    }
}
