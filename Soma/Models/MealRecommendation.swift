import Foundation

/// One AI-suggested recipe from "What can I make?" (generate-meal-
/// recommendation) -- a suggestion the user reviews, cooks, and optionally
/// logs, never auto-saved itself. Mirrors the edge function's camelCase
/// JSON response exactly, same convention as MealEstimate/parse-meal-text.
struct MealRecommendation: Decodable {
    let name: String
    let whyThisMeal: String
    let ingredients: [MealRecommendationIngredient]
    let steps: [MealRecommendationStep]
    /// Subset of the equipment the recipe actually needs -- always a
    /// subset of what the user has on file (household_equipment), never
    /// something outside it; enforced server-side via a closed JSON-schema
    /// enum, not just a prompt instruction.
    let equipmentUsed: [String]
    let totalTimeMinutes: Int
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
}

struct MealRecommendationIngredient: Decodable, Identifiable, Hashable {
    let name: String
    let quantity: String
    var id: String { name }
}

/// One recipe step, optionally carrying a structured wait duration (e.g.
/// "flip the pancakes after 30 seconds" -> durationSeconds: 30) so
/// CookModeView can show a real countdown instead of just prose -- nil
/// for any step that doesn't involve waiting (chopping, seasoning, etc.).
///
/// Custom decoding tolerates a bare string too: `daily_meal_plan` caches
/// a recipe as a jsonb blob, so any row generated before this field
/// existed still has `steps: string[]` on disk. Those rows must keep
/// decoding (as a step with no timer) rather than crashing the whole
/// cached-plan fetch.
struct MealRecommendationStep: Decodable, Identifiable, Hashable {
    let text: String
    let durationSeconds: Int?
    var id: String { text }

    private enum CodingKeys: String, CodingKey {
        case text, durationSeconds
    }

    init(text: String, durationSeconds: Int? = nil) {
        self.text = text
        self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let plain = try? single.decode(String.self) {
            text = plain
            durationSeconds = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
    }
}
