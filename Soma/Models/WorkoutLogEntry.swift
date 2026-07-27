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

    enum CodingKeys: String, CodingKey {
        case id, date, title, category, feedback
        case bodyPart = "body_part"
        case completedAt = "completed_at"
    }
}
