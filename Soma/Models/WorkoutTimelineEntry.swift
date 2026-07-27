import Foundation

/// One actual recorded workout session for the day -- merged client-side
/// from two origins: HealthKit (read on-device, since Apple doesn't let a
/// server read HealthKit) and connected wearables (Oura/Whoop, read via
/// fetch-workout-timeline). Distinct from `WorkoutLogEntry`, which is what
/// the user told Soma they did -- this is what the source actually
/// recorded, shown as a timeline under today's recommendation.
struct WorkoutTimelineEntry: Identifiable {
    let id = UUID()
    let source: String
    let title: String
    let startTime: Date
    let durationMinutes: Int
    let calories: Int?

    var sourceDisplayName: String {
        switch source {
        case "whoop": "Whoop"
        case "oura": "Oura"
        case "apple_health": "Apple Health"
        default: source.capitalized
        }
    }
}
