import Foundation

/// Mirrors a `nutrition_targets` row -- the deterministic (never AI-
/// guessed) Mifflin-St Jeor calorie/macro target computed in
/// analyze-body-photo whenever training_emphasis changes (see
/// supabase/functions/_shared/nutritionTargets.ts). One row per user,
/// recomputed in place -- not a history table.
struct NutritionTargets: Codable {
    let dailyCalories: Int
    let dailyProteinG: Int
    let dailyCarbsG: Int
    let dailyFatG: Int
    let computedAt: String
    /// What formula/inputs produced this -- debugging only, never shown
    /// to the user (e.g. "mifflin_st_jeor:cut:activity=moderate:sex=female").
    let basis: String

    enum CodingKeys: String, CodingKey {
        case dailyCalories = "daily_calories"
        case dailyProteinG = "daily_protein_g"
        case dailyCarbsG = "daily_carbs_g"
        case dailyFatG = "daily_fat_g"
        case computedAt = "computed_at"
        case basis
    }
}
