import Foundation

/// One food item within an estimated or logged meal -- shared between
/// parse-meal-text's response (MealEstimate.ingredients) and a persisted
/// meal_log row (MealLogEntry.ingredientBreakdown), since the server
/// stores exactly the shape it returns, no transformation between the
/// two. gramsEstimate is a Double (server sends a plain JSON number, not
/// necessarily a whole gram count).
struct MealIngredient: Codable, Identifiable, Hashable {
    let name: String
    let gramsEstimate: Double
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case gramsEstimate
        case calories
        case proteinG
        case carbsG
        case fatG
    }
}

/// AI's best-guess calorie/macro breakdown for a freeform food description
/// (e.g. "2 eggs, toast, and coffee with milk"), returned by
/// parse-meal-text. Never saved as-is -- LogMealView shows this back in
/// its normal editable fields so the user reviews/adjusts before it's
/// actually written to meal_log.
///
/// calories/proteinG/carbsG/fatG are the server's SUM of `ingredients`,
/// computed server-side (never an independent second guess from the
/// model) -- see parse-meal-text/estimateBounds.ts's sumIngredients. The
/// four totals stay the primary editable fields in LogMealView exactly
/// as before this per-ingredient redesign; `ingredients` is additional,
/// shown read-only for transparency into what was actually estimated.
struct MealEstimate: Decodable {
    let label: String
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let ingredients: [MealIngredient]
}
