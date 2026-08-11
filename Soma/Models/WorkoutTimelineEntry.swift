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
    /// Nil whenever the source doesn't report it -- Oura's workout
    /// collection never does (no fabricated number in its place); Whoop's
    /// does, when its own API returns it for that session. Defaults nil so
    /// HealthKit-sourced entries (which never carry this) don't need to
    /// pass it explicitly.
    let averageHeartRate: Int?
    let maxHeartRate: Int?

    init(source: String, title: String, startTime: Date, durationMinutes: Int, calories: Int?, averageHeartRate: Int? = nil, maxHeartRate: Int? = nil) {
        self.source = source
        self.title = title
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
    }

    var sourceDisplayName: String {
        switch source {
        case "whoop": return String(localized: "provider.whoop", defaultValue: "Whoop", comment: "Connected-device provider display name; brand name, not translated")
        case "oura": return String(localized: "provider.oura", defaultValue: "Oura", comment: "Connected-device provider display name; brand name, not translated")
        case "apple_health": return String(localized: "provider.appleHealth", defaultValue: "Apple Health", comment: "Connected-device provider display name; brand name, not translated")
        default: return source.capitalized
        }
    }
}
