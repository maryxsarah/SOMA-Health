import Foundation

/// One AI-suggested recipe from "What can I make?" (generate-meal-
/// recommendation) -- a suggestion the user reviews, cooks, and optionally
/// logs, never auto-saved itself. Mirrors the edge function's camelCase
/// JSON response exactly, same convention as MealEstimate/parse-meal-text.
struct MealRecommendation: Decodable {
    let name: String
    let whyThisMeal: String
    let ingredients: [MealRecommendationIngredient]
    let steps: [String]
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
