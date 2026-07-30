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

    enum CodingKeys: String, CodingKey {
        case id, date, title, category, feedback
        case bodyPart = "body_part"
        case completedAt = "completed_at"
        case planSnapshot = "plan_snapshot"
    }
}
