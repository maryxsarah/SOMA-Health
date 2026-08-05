import Foundation

/// Mirrors a `meal_log` row -- manual food-intake entries (source
/// "manual" today; the column also accepts "photo" so a future real
/// meal-scan feature can write into this same table without a schema
/// change). User-entered content, same category as workout_log: no
/// derived/safety logic involved.
struct MealLogEntry: Codable, Identifiable {
    let id: String
    let date: String
    let label: String?
    let calories: Int
    let proteinG: Int
    let carbsG: Int?
    let fatG: Int?
    let source: String
    let loggedAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, label, calories, source
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case loggedAt = "logged_at"
    }
}
