import Foundation

/// Mirrors a `daily_mood` row -- a simple daily "how are you feeling?"
/// check-in (real feedback: "some human-level metric that the app
/// optimizes ... showing that the metric improves with app usage").
/// User-entered content, same category as workout_log/meal_log: no
/// derived/safety logic involved.
struct DailyMoodEntry: Codable, Identifiable {
    let date: String
    let rating: Int
    let loggedAt: String

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, rating
        case loggedAt = "logged_at"
    }
}

/// The 5 fixed options shown on Home's check-in card -- same "closed
/// vocabulary, no freeform number" pattern as WorkoutFeelRating.
enum MoodRating: Int, CaseIterable, Identifiable {
    case rough = 1
    case notGreat = 2
    case okay = 3
    case good = 4
    case great = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .rough: String(localized: "moodRating.rough", defaultValue: "Rough", comment: "Mood check-in option: feeling rough today")
        case .notGreat: String(localized: "moodRating.notGreat", defaultValue: "Not great", comment: "Mood check-in option: feeling not great today")
        case .okay: String(localized: "moodRating.okay", defaultValue: "Okay", comment: "Mood check-in option: feeling okay today")
        case .good: String(localized: "moodRating.good", defaultValue: "Good", comment: "Mood check-in option: feeling good today")
        case .great: String(localized: "moodRating.great", defaultValue: "Great", comment: "Mood check-in option: feeling great today")
        }
    }
}
